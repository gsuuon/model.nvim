local curl = require('llm.curl')
local util = require('llm.util')

local M = {}

local api_key = (function()
  local key

  return function()
    if key == nil then
      key = util.env('OPENAI_API_KEY')
    end

    return key
  end
end)()

local function extract_data(event_string)
  local success, data = pcall(util.json.decode, event_string:gsub('^data: ', ''))

  if success and data ~= nil and data.choices ~= nil then
    return {
      content = (data.choices[1].delta or {}).content,
      finish_reason = data.choices[1].finish_reason
    }
  end
end

function M.default_builder(input)
  return {
    messages = {
      {
        content = input,
        role = 'user',
      }
    }
  }
end

---@param handlers StreamHandlers
---@param params? any Additional options for OpenAI endpoint
function M.request_completion_stream(handlers, params)
  local _all_content = ''

  -- TODO should handlers being optional be a choice at the provider level or always optional for all providers?
  local _handlers = vim.tbl_extend("force", {
    on_partial = util.noop,
    on_finish = util.noop,
    on_error = util.noop,
  }, handlers)

  local function handle_raw(raw_data)
    local items = util.string.split_pattern(raw_data, '\n\ndata: ')
    -- FIXME it seems like sometimes we don't get the two newlines (e.g. before the last [DONE])

    for _, item in ipairs(items) do
      local data = extract_data(item)

      if data ~= nil then
        if data.content ~= nil then
          _all_content = _all_content .. data.content
          _handlers.on_partial(data.content)
        end

        if data.finish_reason ~= nil then
          _handlers.on_finish(_all_content, data.finish_reason)
        end
      else
        local response = util.json.decode(item)

        if response ~= nil then
          _handlers.on_error(response, 'response')
        else
          if not item:match('%[DONE%]') then
            _handlers.on_error(item, 'item')
          end
        end
      end
    end
  end

  local function handle_error(error)
    _handlers.on_error(error, 'curl')
  end

  local body = vim.tbl_deep_extend('force', M.default_request_params, params)

  return curl.stream({
    headers = {
      Authorization = 'Bearer ' .. api_key(),
      ['Content-Type']= 'application/json',
    },
    method = 'POST',
    url = 'https://api.openai.com/v1/chat/completions',
    body = body
  }, handle_raw, handle_error)
end

M.default_request_params = {
  model = 'gpt-3.5-turbo',
  stream = true
}


function M.initialize(opts)
  M.default_request_params = vim.tbl_deep_extend('force',
    M.default_request_params,
    opts or {},
    {
      stream = true -- force streaming since data parsing will break otherwise
    })
end

M.prompt = {}

function M.prompt.input_as_message(input)
  return {
    role = 'user',
    content = input
  }
end

function M.prompt.add_args_as_last_message(messages, context)
  if #context.args > 0 then
    table.insert(messages, {
      role = 'user',
      content = context.args
    })
  end

  return messages
end

function M.prompt.input_and_args_as_messages(input, context)
  return {
    messages =
      M.add_args_as_last_message(
        M.input_as_message(input),
        context
      )
  }
end

function M.prompt.with_system_message(text)
  return function(input, context)
    local body = M.input_and_args_as_messages(input, context)

    table.insert(body.messages, 1, {
      role = 'system',
      content = text
    })

    return body
  end
end

return M
