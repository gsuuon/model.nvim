local M = {}

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

M.json = {}

function M.json.decode(string)
  return vim.json.decode(string, {
    luanil = {
      object = true,
      array = true
    }
  })
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

M.COL_ENTIRE_LINE = vim.v.maxcol

M.buf = {}

function M.buf.text(selection)
  return table.concat(vim.api.nvim_buf_get_text(
    0,
    selection.start.row,
    selection.start.col,
    selection.stop.row,
    selection.stop.col == M.COL_ENTIRE_LINE and 0 or selection.stop.col,
    {}
  ), "\n")
end

return M
