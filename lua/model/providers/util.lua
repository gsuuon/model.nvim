local M = {}

---@deprecated Use iter_sse_messages or iter_sse_data. This doesn't account for partial raw_data (where a single JSON object is split between multiple outputs/data values)
function M.iter_sse_items(raw_data, fn)
  local util = require('model.util')

  local items = util.string.split_pattern(raw_data, 'data:')
  -- FIXME it seems like sometimes we don't get the two newlines?

  for _, item in ipairs(items) do
    if #item > 0 then
      fn(item)
    end
  end
end

-- https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#data
local function parse_sse_message(message_text)
  local message = {}
  local data = {}

  local split_lines = vim.split(message_text, '\n')

  for _,line in ipairs(split_lines) do
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

function M.iter_sse_messages(fn)
  local pending_output = ''

  return function(raw)
    raw = raw:gsub('\r', '') -- handle some providers using \r
    pending_output = pending_output .. '\n' .. raw

    pending_output = pending_output:gsub('(.-)\n\n', function(message)
      fn(parse_sse_message(message))
      return '' -- replace the matched part with empty
    end)
  end
end

---@deprecated Use sse_client
function M.iter_sse_data(fn)
  return M.iter_sse_messages(function(message)
    if message.data ~= nil then
      fn(message.data)
    end
  end)
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

---@param handlers SseHandler
---@return SseClient client
function M.sse_client(handlers)
  local is_sse = false
  local pending = ''

  local function consume_sse_messages()
    -- replaces the matched message with empty
    pending = pending:gsub('(.-)\n\n', function(message)
      handlers.on_message(parse_sse_message(message), pending)
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
      elseif raw:match('^data:') then
        is_sse = true
        consume_sse_messages()
      end
    end,
    on_error = handlers.on_error,
    on_exit = function()
      if #pending > 0 then
        if is_sse then
          handlers.on_message(parse_sse_message(pending), pending)
        else
          handlers.on_other(pending)
        end
      end
    end
  }
end

return M
