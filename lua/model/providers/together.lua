local util = require('model.util')
local curl = require('model.util.curl')
local p_util = require('model.providers.util')

---@type Provider
local M = {
  request_completion = function (handler, params)
    return curl.stream(
      {
        url = 'https://api.together.xyz/inference',
        headers = {
          ['Authorization'] = 'Bearer ' .. util.env('TOGETHER_API_KEY'),
          ['accept'] = 'application/json',
          ['Content-Type'] = 'application/json'
        },
        body = vim.tbl_extend('force', params, {
          stream = true
        })
      },
      p_util.iter_sse_data(function(data)
        if data == '[DONE]' then
          handler.on_finish()
        else
          local item = util.json.decode(data)

          if item == nil then
            return
          end

          if item.choices then
            handler.on_partial(item.choices[1].text)
            return
          end

          util.show(data, 'Unexpected data')
        end
      end),
      function(err)
        handler.on_error(vim.inspect(err), 'Together provider error')
      end
    )
  end
}

return M
