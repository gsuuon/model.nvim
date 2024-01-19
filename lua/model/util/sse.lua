local curl = require('model.util.curl')

local M = {}

-- https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#data
function M.parse_message(message_text)
  local message = {}
  local data = {}

  local split_lines = vim.split(message_text, '\n')

  for _, line in ipairs(split_lines) do
    local label, value = line:match('(.-):%s?(.+)')

    if label ~= nil and label ~= '' then
      if label == 'data' then
        table.insert(data, value)
      else
        message[label] = value
      end
    end
  end

  message.data = table.concat(data, '\n')

  return message
end

---Handles Server-Sent Event messages as well as non-SSE responses
---@class SseHandler
---@field on_message fun(msg: {data:string, [string]:string }, pending: string): nil
---@field on_other fun(out: string): nil
---@field on_error fun(out: string): nil

---Exposes handlers for curl output and translates for use with SSE handlers
---@class SseClient
---@field on_stdout fun(raw: string):nil
---@field on_error fun(err: string, label?: string):nil
---@field on_exit fun():nil
---@field on_headers fun(headers: string):nil

---@param handlers SseHandler
---@return SseClient client
function M.client(handlers)
  local is_sse = false
  local pending = ''

  local function consume_sse_messages()
    -- replaces the matched message with empty
    pending = pending:gsub('(.-)\n\n', function(message)
      handlers.on_message(M.parse_message(message), pending)
      return ''
    end)
  end

  return {
    on_stdout = function(raw)
      -- each raw can contain:
      --  partial of not an sse message
      --  complete not sse message
      --  partial sse message
      --  complete sse message
      --  complete multiple sse message
      --  partial of multiple sse message

      pending = pending .. raw

      if is_sse then
        consume_sse_messages()
      elseif raw:match('^data:') then -- In case the provider didn't send correct headers
        -- TODO is this useful?
        is_sse = true
        consume_sse_messages()
      end
    end,
    on_error = handlers.on_error,
    on_exit = function()
      if #pending > 0 then
        if is_sse then
          handlers.on_message(M.parse_message(pending), pending)
        else
          handlers.on_other(pending)
        end
      end
    end,
    on_headers = function(headers)
      if headers:match('[Cc]ontent%-[Tt]ype:%s?text/event%-stream') then
        is_sse = true
      end
    end,
  }
end

---@param opts { url : string, method : string, body : any, headers : {[string]: string} }
---@param handler SseHandler
---@return fun ():nil cancel
function M.curl_client(opts, handler)
  local sse = M.client(handler)

  return curl.stream(
    opts,
    sse.on_stdout,
    sse.on_error,
    sse.on_exit,
    sse.on_headers
  )
end

return M
