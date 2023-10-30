local curl = require('llm.curl')
local util = require('llm.util')
local provider_util = require('llm.providers.util')

local M = {}

---@param handlers StreamHandlers
---@param params any Parameters for endpoint
---@param options? { url?: string } Url defaults to 'http://localhost:5001/api/extra/generate/stream'
function M.request_completion(handlers, params, options)
  options = options or {}

  local url_ = options.url or 'http://localhost:5001/api/extra/generate/stream'

  return curl.stream(
    {
      url = url_,
      method = 'POST',
      body = params,
      headers = {
        ['Content-Type'] = 'application/json'
      }
    },
    provider_util.iter_sse_messages(
      function(message)
        if message.data == nil then return end
        local item = message.data

        local data, err = util.json.decode(item)

        if data == nil then
          if not (item:match('^event: message') or item:match('^HTTP/1.0 200 OK')) then
            util.eshow(item, 'failed to parse server-sent event')
            error(err)
          end
        else
          handlers.on_partial(data.token)
        end
      end
    ),
    util.eshow
  )
end

return M
