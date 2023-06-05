-- All positions should be 0-indexed

local M = {}

function M.noop() end

local function show(item, level, opt)
  local _body = type(item) == 'string' and item or vim.inspect(item)
  local _level = level or vim.log.levels.INFO

  local _opt =
    opt == nil and {} or
    type(opt) == 'string' and { title = opt } or
    opt

  vim.notify(_body, _level, _opt)
end

function M.show(item, opt)
  show(item, vim.log.levels.INFO, opt)
end

function M.eshow(item, opt)
  if type(item) == 'table' and item.message ~= nil and item.stack ~= nil then
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

function M.env(name)
  local value = os.getenv(name)

  if value == nil then
    M.error('Missing environment variable: ' .. name)
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

  local _cur = ''

  for i = 1, #text do
    local char = text:sub(i, i)

    if char == sep then
      table.insert(res, _cur)
      _cur = ''
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

M.position = {}

-- b is less than a
function M.position.is_less(a, b)
  if a.row == b.row then
    return b.col < a.col
  end

  return b.row < a.row
end

-- b is greater or equal to a
function M.position.is_greater_eq(a, b)
  return not M.position.is_less(a, b)
end

-- pos is between start (inclusive) and final (exclusive)
-- false if pos == start == final
function M.position.is_bounded(pos, start, stop)
  return M.position.is_greater_eq(start, pos) and M.position.is_less(stop, pos)
end

M.COL_ENTIRE_LINE = vim.v.maxcol or 2147483647

M.buf = {}

function M.buf.text(selection)
  return vim.api.nvim_buf_get_text(
    0,
    selection.start.row,
    selection.start.col,
    selection.stop.row,
    selection.stop.col == M.COL_ENTIRE_LINE and -1 or selection.stop.col,
    {}
  )
end

function M.buf.set_text(selection, lines)
  local stop_col =
    selection.stop.col == M.COL_ENTIRE_LINE
      and #assert(
            vim.api.nvim_buf_get_lines(0, selection.stop.row, selection.stop.row + 1, true)[1],
            'No line at ' .. tostring(selection.stop.row)
          )
      or selection.stop.col

  vim.api.nvim_buf_set_text(
    0,
    selection.start.row,
    selection.start.col,
    selection.stop.row,
    stop_col,
    lines
  )
end

function M.buf.filename()
  return vim.fs.normalize(vim.fn.expand('%:.'))
end

---@param callback function
---@param initial_content? string | string[]
---@param title? string
function M.buf.prompt(callback, initial_content, title)
  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'prompt')

  vim.cmd(':b ' .. bufnr)

  vim.api.nvim_set_option_value('winbar', title or 'Prompt', { scope = 'local' })

  if initial_content ~= nil then
    if type(initial_content) == "string" then
      initial_content = vim.fn.split(initial_content, '\n')
    end
    vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, initial_content)
  end

  vim.fn.prompt_setcallback(bufnr, function(user_input)
    local buf_content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -3, false), '\n')
    local success, result = pcall(callback, user_input, buf_content)

    if not success then
      vim.notify(result, vim.log.levels.ERROR)
    end

    vim.cmd(':bd! ' .. bufnr)
  end)

  vim.cmd.startinsert()
end

M.module = {}

--- Re-require a module on access. Useful when developing a prompt library to avoid restarting nvim.
--- Plenty of gotchas here (need special function for pairs, perf is bad) so shouldn't be used always
function M.module.autoload(package_name)
  local mod = {}

  local stale = true

  local function load()
    if stale then
      package.loaded[package_name] = nil

      stale = false

      vim.defer_fn(function()
        stale = true
      end, 1)
    end

    return require(package_name)
  end

  setmetatable(mod, {
    __index = function(_, key)
      return load()[key]
    end,
  })

  mod.__autopairs = function()
    return pairs(load())
  end

  return mod
end

--- Pairs for autoloaded modules. Safe to use on all tables.
--- __pairs metamethod isn't available in Lua 5.1
function M.module.autopairs(table)
  if table.__autopairs ~= nil then
    return table.__autopairs()
  end

  return pairs(table)
end

return M
