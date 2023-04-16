local M = {}

function M.noop() end

-- All positions should be 0-indexed
function M.env(name)
  local value = os.getenv(name)

  if value == nil then
    error("Missing environment variable: " .. name)
  else
    return value
  end
end

function M.delay(timeout, fn)
  local timer = vim.loop.new_timer()
  timer:start(timeout, 0, vim.schedule_wrap(fn))
end

M.table = {}

function M.table.slice(tbl, start, fin)
  return {table.unpack(tbl, start, fin)}
end


function M.table.map_to_array(table, fn)
  local result = {}
  local idx = 1

  for k,v in pairs(table) do
    result[idx] = fn(k, v)
    idx = idx + 1
  end

  return result
end

M.json = {}

function M.json.decode(string)
  local success, obj = pcall(vim.json.decode, string, {
    -- obj is error message if not success
    luanil = {
      object = true,
      array = true
    }
  })

  if success then return obj end
end

M.string = {}

function M.string.split(text, sep)
  local res = {}

  local _cur = ""

  for i = 1, #text do
    local char = text:sub(i, i)

    if char == sep then
      table.insert(res, _cur)
      _cur = ""
    else
      _cur = _cur .. char
    end
  end

  table.insert(res, _cur)

  return res
end

function M.string.split_pattern(text, pattern)
  -- gpt made this

  local parts = {}
  local start_index = 1

  repeat
    local end_index = string.find(text, pattern, start_index)

    if end_index == nil then
      end_index = #text + 1
    end

    local part = string.sub(text, start_index, end_index - 1)

    table.insert(parts, part)
    start_index = end_index + #pattern

  until start_index > #text

  return parts
end

M.cursor = {}

function M.cursor.selection()
  local start = vim.fn.getpos("'<")
  local stop = vim.fn.getpos("'>")

  -- stop col can be int32 limit, which means entire line

  return {
    start = {
      row = start[2] - 1,
      col = start[3] - 1
    },
    stop = {
      row = stop[2] - 1,
      col = stop[3]
    }
  }
end

function M.cursor.position()
  local pos = vim.api.nvim_win_get_cursor(0)

  return {
    row = pos[1] - 1,
    col = pos[2]
  }
end

M.COL_ENTIRE_LINE = vim.v.maxcol

M.buf = {}

function M.buf.text(selection)
  return table.concat(vim.api.nvim_buf_get_text(
    0,
    selection.start.row,
    selection.start.col,
    selection.stop.row,
    selection.stop.col == M.COL_ENTIRE_LINE and -1 or selection.stop.col,
    {}
  ), "\n")
end

return M
