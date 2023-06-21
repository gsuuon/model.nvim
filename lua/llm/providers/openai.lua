local curl = require('llm.curl')
local util = require('llm.util')
local provider_util = require('llm.providers.util')

local M = {}

M.name = 'openai'

local function extract_chat_data(item)
  local data = util.json.decode(item)

  if data ~= nil and data.choices ~= nil then
    return {
      content = (data.choices[1].delta or {}).content,
      finish_reason = data.choices[1].finish_reason
    }
  end
end

local function extract_completion_data(item)
  local data = util.json.decode(item)
  if data ~= nil and data.choices ~= nil then
    return {
      content = (data.choices[1] or {}).text,
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
---@param options { endpoint: string } Request endpoint, defaults to 'chat/completions'
function M.request_completion(handlers, params, options)
  local _all_content = ''

  local endpoint = (options or {}).endpoint or 'chat/completions'
  local extract_data = endpoint == 'chat/completions' and extract_chat_data or extract_completion_data

  -- TODO should handlers being optional be a choice at the provider level or always optional for all providers?
  local _handlers = vim.tbl_extend("force", {
    on_partial = util.noop,
    on_finish = util.noop,
    on_error = util.noop,
  }, handlers)

  local function handle_raw(raw_data)
    provider_util.iter_sse_items(raw_data, function(item)
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
    end)
  end

  local function handle_error(error)
    _handlers.on_error(error, 'curl')
  end

  local body = vim.tbl_deep_extend('force', M.default_request_params, params)

  return curl.stream({
    headers = {
      Authorization = 'Bearer ' .. util.env_memo('OPENAI_API_KEY'),
      ['Content-Type']= 'application/json',
    },
    method = 'POST',
    url = 'https://api.openai.com/v1/' .. endpoint,
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

M.default_prompt = {
  provider = M,
  builder = M.default_builder,
  params = M.default_request_params
}

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
