local curl = require('llm.curl')
local util = require('llm.util')
local provider_util = require('llm.providers.util')

local M = {}

---@param handlers StreamHandlers
---@param params? any Additional params for request
---@param options? { model?: string }
function M.request_completion(handlers, params, options)
  local model = (options or {}).model or 'bigscience/bloom'

  -- TODO handle non-streaming calls
  return curl.stream(
    {
      url = 'https://api-inference.huggingface.co/models/' .. model,
      method = 'POST',
      body = vim.tbl_extend('force', { stream = true }, params),
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
        if data.generated_text ~= nil and #data.generated_text > 0 then
          handlers.on_finish(data.generated_text, 'stop')
        end
      end)
    end,
    function(error)
      handlers.on_error(error)
    end
  )
end

M.default_prompt = {
  provider = M,
  options = {
    model = 'bigscience/bloom'
  },
  params = {
    return_full_text = false
  },
  builder = function(input)
    return { inputs = input }
  end
}

return M
