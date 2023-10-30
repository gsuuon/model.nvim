local M = {}

local function parse_sse_message(message_text)
  local message = {}
  local data = {}

  local split_lines = vim.fn.split(message_text, '\n')
  ---@cast split_lines string[]

  for _,line in ipairs(split_lines) do
    local label, value = line:match('(.-): (.+)')

    if label == 'data' then
      table.insert(data, value)
    elseif label ~= '' then
      message[label] = value
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
