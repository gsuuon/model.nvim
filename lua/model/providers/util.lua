local sse = require('model.util.sse')

local M = {}

---@deprecated Use require('model.util.sse').client
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

---@deprecated Use require('model.util.sse').client
function M.iter_sse_messages(fn)
  local pending_output = ''

  return function(raw)
    raw = raw:gsub('\r', '') -- handle some providers using \r
    pending_output = pending_output .. '\n' .. raw

    pending_output = pending_output:gsub('(.-)\n\n', function(message)
      fn(sse.parse_message(message))
      return '' -- replace the matched part with empty
    end)
  end
end

---@deprecated Use require('model.util.sse').client
function M.iter_sse_data(fn)
  return M.iter_sse_messages(function(message)
    if message.data ~= nil then
      fn(message.data)
    end
  end)
end

return M
