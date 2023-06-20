local curl = require('llm.curl')
local util = require('llm.util')
local provider_util = require('llm.providers.util')

local M = {}

M.name = 'huggingface'

---@param handlers StreamHandlers
---@param params? any Additional options for OpenAI endpoint
function M.request_completion(handlers, params)
  local model = params.model or 'bigscience/bloom'
  params.model = nil
  params.stream = params.stream == nil and true or params.stream

  -- TODO handle non-streaming calls
  return curl.stream(
    {
      url = 'https://api-inference.huggingface.co/models/' .. model,
      method = 'POST',
      body = params,
      headers = {
        Authorization = 'Bearer ' .. util.env_memo('HUGGINGFACE_API_KEY'),
        ['Content-Type'] = 'application/json'
      }
    },
    function(raw)
      provider_util.iter_sse_items(raw, function(item)
        local data = util.json.decode(item)

        if data == nil then
          handlers.on_error(item, 'json parse error')
          return
        end

        if data.token == nil then
          if data[1] ~= nil and data[1].generated_text ~= nil then
            -- non-streaming
            handlers.on_finish(data[1].generated_text, 'stop')
            return
          end

          handlers.on_error(data, 'missing token')
          return
        end

        local partial = data.token.text

        handlers.on_partial(partial)

        -- We get the completed text including input unless parameters.return_full_text is set to false
        -- if data.generated_text ~= nil and #data.generated_text > 0 then
        --   handlers.on_finish(data.generated_text, 'stop')
        -- end
      end)
    end,
    function(error)
      handlers.on_error(error)
    end
  )
end

return M
