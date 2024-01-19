local util = require('model.util')
local sse = require('model.util.sse')

--- https://docs.together.ai/docs/inference-models
--- https://docs.together.ai/docs/inference-parameters
---@type Provider
local M = {
  request_completion = function(handler, params)
    return sse.curl_client({
      url = 'https://api.together.xyz/inference',
      headers = {
        ['Authorization'] = 'Bearer ' .. util.env('TOGETHER_API_KEY'),
        ['Accept'] = 'application/json',
        ['Content-Type'] = 'application/json',
      },
      body = vim.tbl_extend('force', params, {
        stream = true,
      }),
    }, {
      on_message = function(msg, pending)
        local item = util.json.decode(msg.data)

        if item and item.choices then
          handler.on_partial(item.choices[1].text)
        elseif msg.data == '[DONE]' then
          handler.on_finish()
        else
          handler.on_error(pending, 'Unrecognized SSE response')
        end
      end,
      on_error = handler.on_error,
      on_other = handler.on_error,
    })
  end,
}

return M
