local util = require('model.util')
local sse = require('model.util.sse')

--- Anthropic provider
--- options:
--- {
---   headers: table,
---   trim_code?: boolean -- streaming trim leading newline and trailing codefence
--- }
---@class Provider
local M = {
  request_completion = function(handler, params, options)
    options = options or {}

    local consume = handler.on_partial
    local finish = function() end

    if options.trim_code then
      -- we keep 1 partial in buffer so we can strip the leading newline and trailing markdown block fence
      local last = nil

      ---@param partial string
      consume = function(partial)
        if last then
          handler.on_partial(last)
          last = partial
        else -- strip the first leading newline
          last = partial:gsub('^\n', '')
        end
      end

      finish = function()
        if last then
          -- ignore the trailing codefence
          handler.on_partial(last:gsub('\n```$', ''))
        end
      end
    end

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
      on_message = function(msg)
        local data = util.json.decode(msg.data)

        if msg.event == 'content_block_delta' then
          consume(data.delta.text)
        elseif msg.event == 'message_delta' then
          util.show(data.usage.output_tokens, 'output tokens')
        elseif msg.event == 'message_stop' then
          finish()
        end
      end,
      on_error = handler.on_error,
      on_other = handler.on_error,
      on_exit = handler.on_finish,
    })
  end,
}

local function cache_content(content)
  return {
    {
      type = 'text',
      text = content,
      cache_control = {
        type = 'ephemeral',
      },
    },
  }
end

---@param content string
M.cache_if_prefixed = function(content)
  if content:match('^>> cache\n') then
    return cache_content(content:gsub('^>> cache\n', ''))
  else
    return content
  end
end

return M
