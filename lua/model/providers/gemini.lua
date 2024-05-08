local util = require('model.util')
local sse = require('model.util.sse')

---@type Provider
local M = {
  request_completion = function(handler, params)
    return sse.curl_client({
      url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:streamGenerateContent?alt=sse&key='
        .. util.env('GOOGLE_API_KEY'),
      headers = {
        ['Content-Type'] = 'application/json',
      },
      body = params,
    }, {
      on_message = function(msg, raw)
        local item = util.json.decode(msg.data)
        if item and item.candidates then
          if item.candidates[1].content then
            local text_parts = item.candidates[1].content.parts
            for _, part in ipairs(text_parts) do
              handler.on_partial(part.text)
            end
          else
            handler.on_error(item)
          end
        else
          local err_response = util.json.decode(raw)

          if err_response then
            handler.on_error(err_response)
          else
            handler.on_error('Unrecognized SSE response')
          end
        end
      end,
      on_error = handler.on_error,
      on_other = handler.on_error,
      on_exit = handler.on_finish,
    })
  end,
}

return M
