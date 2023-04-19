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

function M.default_builder(input, _)
  return {
    messages = {
      { content = input,
        role = 'user'
      }
    }
  }
end

---@param input string
---@param handlers StreamHandlers
---@param prompt fun(input: string, context: table): table Converts input (selection) to a table to be merged into request body
---@param params? any Additional options for OpenAI endpoint
function M.request_completion_stream(input, handlers, prompt, params)
  local _all_content = ''

  local function handle_raw(raw_data)
    local items = util.string.split_pattern(raw_data, '\n\ndata: ')

    for _, item in ipairs(items) do
      local data = extract_data(item)

      if data ~= nil then
        if data.content ~= nil then
          _all_content = _all_content .. data.content
          handlers.on_partial(data.content)
        end

        if data.finish_reason ~= nil then
          handlers.on_finish(_all_content, data.finish_reason)
        end
      else
        local response = util.json.decode(item)

        if response ~= nil then
          handlers.on_error(response, 'response')
        else
          if not item:match('^%[DONE%]') then
            handlers.on_error(item, 'item')
          end
        end
      end
    end
  end

  local function handle_error(error)
    handlers.on_error(error, 'curl')
  end

  return curl.stream({
    headers = {
      Authorization = 'Bearer ' .. api_key(),
      ['Content-Type']= 'application/json',
    },
    method = 'POST',
    url = 'https://api.openai.com/v1/chat/completions',
    body =
      vim.tbl_deep_extend('force',
        M.default_request_params,
        (params or {}),
        prompt(input, {
          filename = util.buf.filename()
        })
      )
  }, handle_raw, handle_error)
end

function M.initialize(opts)
  M.default_request_params = vim.tbl_deep_extend('force',
    {
      model = 'gpt-3.5-turbo'
    },
    opts or {},
    {
      stream = true -- force streaming since data parsing will break otherwise
    })
end

return M
