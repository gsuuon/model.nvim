local curl = require('llm.util.curl')
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
    provider_util.iter_sse_data(
      function(data)
        local item, err = util.json.decode(data)

        if item == nil then
          util.eshow(data, 'failed to parse server-sent event')
          error(err)
        else
          handlers.on_partial(item.token)
        end
      end
    ),
    util.eshow
  )
end

return M
