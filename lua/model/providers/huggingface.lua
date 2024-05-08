local util = require('model.util')
local sse = require('model.util.sse')

local M = {}

---@param handlers StreamHandlers
---@param params? any Additional params for request. Note the parameters detailed at https://huggingface.co/docs/api-inference/detailed_parameters need to go in the `params.parameters` field.
---@param options? { model?: string }
function M.request_completion(handlers, params, options)
  local model = (options or {}).model or 'bigscience/bloom'

  -- TODO handle non-streaming calls
  return sse.curl_client({
    url = 'https://api-inference.huggingface.co/models/' .. model,
    method = 'POST',
    body = vim.tbl_extend('force', { stream = true }, params),
    headers = {
      Authorization = 'Bearer ' .. util.env('HUGGINGFACE_API_KEY'),
      ['Content-Type'] = 'application/json',
    },
  }, {
    on_message = function(msg)
      local item = util.json.decode(msg.data)

      if item == nil then
        handlers.on_error(msg.data, 'json parse error')
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
    end,
  })
end

M.default_prompt = {
  provider = M,
  options = {
    model = 'bigscience/bloom',
  },
  params = {
    parameters = {
      return_full_text = false,
    },
  },
  builder = function(input)
    return { inputs = input }
  end,
}

return M
