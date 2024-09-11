local util = require('model.util')
local curl = require('model.util.curl')

local M = {}

function M.request_completion(handlers, params, options)
  -- vim.notify(vim.inspect({ handlers = handlers }))
  -- vim.notify(vim.inspect({ params = params, options = options }))

  request_body = vim.tbl_deep_extend('force', params, options)
  -- vim.notify(vim.inspect({ request_body = request_body }))

  return curl.request({
    url = 'https://api.groq.com/openai/v1/chat/completions',
    method = 'POST',
    headers = {
      Authorization = 'Bearer ' .. util.env('GROQ_API_KEY'),
      ['Content-Type'] = 'application/json',
    },
    body = request_body,
  }, function(response)
    local data = util.json.decode(response)
    -- vim.notify(vim.inspect({ data = data }))
    if data == nil then
      handlers.on_error('Failed to decode Groq API response: ' .. response)
      error('Failed to decode Groq API response: ' .. response)
    end
    -- TODO : use other returned stats as well?
    assistant_message = data.choices[1].message.content
    handlers.on_finish(assistant_message, 'stop')
  end, handlers.on_error)
end

return M
