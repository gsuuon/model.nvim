local curl = require('model.util.curl')
local util = require('model.util')
local provider_util = require('model.providers.util')

local M = {}

local function parse_llmchain_data(item)
  local data = util.json.decode(item)

  if data ~= nil and data["text"] ~= nil then
    return {
      content = data["text"]
    }
  end
end

---@param handlers StreamHandlers
---@param params? any Additional options for OpenAI endpoint
---@param options? { output_parser: FunctionItem, base_url?: string } Request endpoint and url. Defaults to 'https://api.openai.com/v1/' and 'chat/completions'. `authorization` overrides the request auth header. If url is provided the environment key will not be sent, you'll need to provide an authorization.
function M.request_completion(handlers, params, options)
  local _all_content = ''
  options = options or {}

  local endpoint = 'stream'

  local extract_data = options.output_parser

  -- TODO should handlers being optional be a choice at the provider level or always optional for all providers?
  local _handlers = vim.tbl_extend("force", {
    on_partial = util.noop,
    on_finish = util.noop,
    on_error = util.noop,
  }, handlers)

  local handle_raw = provider_util.iter_sse_messages(function(message)
    if message.event == "metadata" then
      return
    end

    if message.event == "end" then
      _handlers.on_finish(_all_content)
      return
    end

    local data = extract_data(message.data)

    if data ~= nil then
      if data.content ~= nil then
        _all_content = _all_content .. data.content
        _handlers.on_partial(data.content)
      end

    else
      local response = util.json.decode(message)

      if response ~= nil then
        _handlers.on_error(response, 'response')
      else
        -- TODO?
        -- if not message:match('%[DONE%]') then
        --   _handlers.on_error(message, 'message')
        -- end
      end
    end
  end)

  local function handle_error(error)
    _handlers.on_error(error, 'curl')
  end

  -- local body = vim.tbl_deep_extend('force', default_params, params)
  local body = {
      input = params,
  }

  local headers = { ['Content-Type'] = 'application/json' }

  local url_ = options.base_url
  if url_ then
    -- ensure we have a trailing slash if url was provided by options
    if not url_:sub(-1) == '/' then
      url_ = url_ .. '/'
    end
  else
    -- default to local langserve
    url_ = 'http://127.0.0.1:8000/'
  end

  return curl.stream({
    headers = headers,
    method = 'POST',
    url = url_ .. endpoint,
    body = body,
  }, handle_raw, handle_error)
end

--- Sets default openai provider params. Currently enforces `stream = true`.
function M.initialize(opts)
  default_params = vim.tbl_deep_extend('force',
    default_params,
    opts or {},
    {
      stream = true -- force streaming since data parsing will break otherwise
    })
end

M.llmchain_output_parser = parse_llmchain_data

return M
