local curl = require('model.util.curl')
local util = require('model.util')
local provider_util = require('model.providers.util')

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
    provider_util.iter_sse_data(function(data)
      local item = util.json.decode(data)

      if item == nil then
        handlers.on_error(data, 'json parse error')
        return
      end

      if item.token == nil then
        if item[1] ~= nil and item[1].generated_text ~= nil then
          -- non-streaming
          handlers.on_finish(item[1].generated_text, 'stop')
          return
        end

        handlers.on_error(item, 'missing token')
        return
      end

      local partial = item.token.text

      handlers.on_partial(partial)

      -- We get the completed text including input unless parameters.return_full_text is set to false
      if item.generated_text ~= nil and #item.generated_text > 0 then
        handlers.on_finish(item.generated_text, 'stop')
      end
    end),
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
