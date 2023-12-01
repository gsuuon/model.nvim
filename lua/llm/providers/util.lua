local M = {}

---@deprecated Use iter_sse_messages or iter_sse_data. This doesn't account for partial raw_data (where a single JSON object is split between multiple outputs/data values)
function M.iter_sse_items(raw_data, fn)
  local util = require('llm.util')

  local items = util.string.split_pattern(raw_data, 'data:')
  -- FIXME it seems like sometimes we don't get the two newlines?

  for _, item in ipairs(items) do
    if #item > 0 then
      fn(item)
    end
  end
end

local function parse_sse_message(message_text)
  local message = {}
  local data = {}

  local split_lines = vim.fn.split(message_text, '\n')
  ---@cast split_lines string[]

  for _,line in ipairs(split_lines) do
    local label, value = line:match('(.-): (.+)')

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
    pending_output = pending_output .. '\n' .. raw

    pending_output = pending_output:gsub('(.-)\n\n', function(message)
      fn(parse_sse_message(message))
      return '' -- replace the matched part with empty
    end)
  end
end

function M.iter_sse_data(fn)
  return M.iter_sse_messages(function(message)
    if message.data ~= nil then
      fn(message.data)
    end
  end)
end

return M
