local M = {}

function M.noop() end

local function show(item, level, opt)
  local _body = type(item) == "string" and item or vim.inspect(item)
  local _level = level or vim.log.levels.INFO

  local _opt =
    opt == nil and {} or
    type(opt) == "string" and { title = opt } or
    opt

  vim.notify(_body, _level, _opt)
end

function M.show(item, opt)
  show(item, vim.log.levels.INFO, opt)
end

function M.eshow(item, opt)
  if type(item) == "table" and item.message ~= nil and item.stack ~= nil then
    show(
      item.message .. '\n' .. item.stack,
      vim.log.levels.ERROR,
      opt
    )
  else
    show(
      item,
      vim.log.levels.ERROR,
      opt
    )
  end
end

function M.error(message)
  error({
    message = message,
    stack = debug.traceback('', 2)
  })
end

-- All positions should be 0-indexed
function M.env(name)
  local value = os.getenv(name)

  if value == nil then
    M.error("Missing environment variable: " .. name)
  else
    return value
  end
end

M.table = {}

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

function M.string.split_char(text, sep)
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

  return {
    start = {
      row = start[2] - 1,
      col = start[3] - 1
    },
    stop = {
      row = stop[2] - 1,
      col = stop[3] -- stop col can be vim.v.maxcol which means entire line
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

M.COL_ENTIRE_LINE = vim.v.maxcol or 2147483647

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

function M.buf.filename()
  return vim.fs.normalize(vim.fn.expand('%:.'))
end

return M
