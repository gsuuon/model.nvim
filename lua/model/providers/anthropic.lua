local util = require('model.util')
local sse = require('model.util.sse')

---@type Provider
local M = {
  request_completion = function(handler, params, options)
    options = options or {}

    return sse.curl_client({
      url = 'https://api.anthropic.com/v1/messages',
      headers = vim.tbl_extend('force', {
        ['Content-Type'] = 'application/json',
        ['x-api-key'] = util.env('ANTHROPIC_API_KEY'),
        ['anthropic-beta'] = 'messages-2023-12-15',
        ['anthropic-version'] = '2023-06-01',
      }, options.headers or {}),
      body = vim.tbl_deep_extend('force', {
        max_tokens = 1024, -- required field
      }, params, { stream = true }),
    }, {
      on_message = function(msg, raw)
        local data = util.json.decode(msg.data)

        if msg.event == 'content_block_start' then
          handler.on_partial(data.content_block.text)
        elseif msg.event == 'content_block_delta' then
          handler.on_partial(data.delta.text)
        elseif msg.event == 'message_delta' then
          util.show(data.usage.output_tokens, 'output tokens')
          -- else
          --   util.show(msg, 'msg')
        end
      end,
      on_error = handler.on_error,
      on_other = handler.on_error,
      on_exit = handler.on_finish,
    })
  end,
}

return M
