-- All positions should be 0-indexed

local M = {}

M.secrets = {}

function M.noop(_) end

function M.notify(msg, level, opts)
  if vim.in_fast_event() then
    vim.schedule(function()
      vim.notify(msg, level, opts)
    end)
  else
    vim.notify(msg, level, opts)
  end
end

local function show(item, level, opt)
  local _body = type(item) == 'string' and item or vim.inspect(item)
  local _level = level or vim.log.levels.INFO

  local _opt = opt == nil and {}
    or type(opt) == 'string' and { title = opt }
    or opt

  M.notify(_body, _level, _opt)
end

function M.show(item, opt)
  show(item, vim.log.levels.INFO, opt)
end

function M.eshow(item, opt)
  if type(item) == 'table' and item.message ~= nil and item.stack ~= nil then
    show(item.message .. '\n' .. item.stack, vim.log.levels.ERROR, opt)
  else
    show(item, vim.log.levels.ERROR, opt)
  end
end

function M.tap(x, opt)
  M.show(x, opt)
  return x
end

function M.tap_if(x, cond)
  if cond then
    M.show(x)
  end

  return x
end

function M.memo(fn)
  local cache = {}

  return function(x)
    if cache[x] == nil then
      cache[x] = fn(x)
    end

    return cache[x]
  end
end

--- Deep extend 'from' to 'into'
function M.merge(into, from)
  return vim.tbl_deep_extend('force', into, from)
end

M.env = M.memo(function(name)
  if type(M.secrets) == 'function' then
    return M.secrets(name)
  elseif type(M.secrets[name]) == 'function' then
    return M.secrets[name]()
  else
    local value = vim.env[name]

    if value == nil then
      error('Missing environment variable or secret: ' .. name)
    else
      return value
    end
  end
end)

M.table = {}

function M.table.map_to_array(table, fn)
  local result = {}
  local idx = 1

  for k, v in pairs(table) do
    result[idx] = fn(k, v)
    idx = idx + 1
  end

  return result
end

--- Gets the 0-indexed subslice of a list table
function M.table.slice(tbl, start, stop)
  local function idx(x)
    if x >= 0 then
      return x
    else
      return #tbl + x
    end
  end

  local start_idx = start == nil and 0 or idx(start)
  local stop_idx = stop == nil and #tbl or idx(stop)

  if stop_idx < start_idx then
    error('stop (' .. stop_idx .. ') is less than start (' .. start_idx .. ')')
  end

  local results = {}

  for i = start_idx + 1, stop_idx do
    table.insert(results, tbl[i])
  end

  return results
end

--- Flattens a list containing either nested lists or objects.
--- Unlike vim.tbl_flatten, works when lists contain objects (tables) and
--- only flattens up to 1 level.
function M.table.flatten(tbls)
  local results = {}

  for _, x in ipairs(tbls) do
    if type(x) == 'table' and vim.tbl_islist(x) then
      for _, item in ipairs(x) do
        table.insert(results, item)
      end
    else
      table.insert(results, x)
    end
  end

  return results
end

--- Copies table without the given key
function M.table.without(tbl, key)
  local result = {}
  for k, v in pairs(tbl) do
    if k ~= key then
      result[k] = v
    end
  end

  return result
end

M.list = {}

function M.list.equals(as, bs)
  if not vim.tbl_islist(as) or not vim.tbl_islist(bs) then
    return false
  end

  if #as ~= #bs then
    return false
  end

  for i, x in ipairs(as) do
    if bs[i] ~= x then
      return false
    end
  end

  return true
end

function M.list.append(as, bs)
  for _, b in ipairs(bs) do
    table.insert(as, b)
  end

  return as
end

M.json = {}

function M.json.decode(json_string)
  local success, obj = pcall(vim.json.decode, json_string, {
    -- obj is error message if not success
    luanil = {
      object = true,
      array = true,
    },
  })

  if success then
    return obj
  else
    local char_offset = tonumber(obj:match('character (%d+)'))
    if char_offset then
      local start = math.max(1, char_offset - 20)
      local stop = math.min(#json_string, char_offset + 20)
      local context = json_string:sub(start, stop)
      obj = obj .. '\nContext:\n' .. context
    end

    return nil, obj
  end
end

M.string = {}

--TODO replace with vim.split
---@deprecated Just use vim.split
---@param text string
---@param sep string
---@return string[]
function M.string.split_char(text, sep)
  return vim.split(text, sep)
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

--- Removes any surrounding quotes or markdown code blocks
function M.string.trim_quotes(text)
  local open_markers = text:match([=[^['"`]+]=])

  if open_markers == nil then
    return text
  end

  local open = '^' .. open_markers
  local close = open_markers .. '$'

  local result = text:gsub(open, ''):gsub(close, '')

  return result
end

--- Trim markdown code block fence and surrounding quotes
function M.string.trim_code_block(text)
  -- TODO there's probably a simpler way to preserve the surrounding newline semantics
  -- or maybe I don't need is_multiline at all, assume single line blocks are always single backtick
  -- so ```'s always include newlines
  local is_code_block = text:match('^```') and text:match('```$')

  if not is_code_block then
    return text
  end

  local has_fence = text:match('^```[^\n]+\n')

  if has_fence then
    local result = text:gsub('^```[^\n]*\n', ''):gsub('\n?```$', '')
    return result
  end

  local is_multiline = text:match('^```\n') and text:match('\n```$')

  if is_multiline then
    local result = text:gsub('^```\n', ''):gsub('\n```$', '')
    return result
  end

  local result = text:gsub('^```', ''):gsub('```$', '')
  return result
end

-- Extracts markdown code blocks and interspliced explanations into a list of either
-- {code: string, lang: string} or {text: string}
function M.string.extract_markdown_code_blocks(md_text)
  local blocks = {}
  local current_block = { text = '' }
  local in_code_block = false

  local function add_text_block()
    if current_block.text ~= nil and #current_block.text > 0 then
      table.insert(blocks, current_block)
    end
  end

  for line in md_text:gmatch('[^\r\n]+') do
    local code_fence = line:match('^```([%w-]*)')
    if code_fence then
      in_code_block = not in_code_block
      if in_code_block then
        add_text_block()
        current_block = { code = '', lang = code_fence }
      else
        table.insert(blocks, current_block)
        current_block = { text = '' }
      end
    elseif in_code_block then
      current_block.code = current_block.code .. line .. '\n'
    else
      current_block.text = current_block.text .. line .. '\n'
    end
  end

  add_text_block()
  return blocks
end

---@deprecated Use util.path.join()
function M.string.joinpath(...)
  return M.path.join(...)
end

M.path = {}

function M.path.join(...)
  -- can eventually be replaced by vim.fn.joinpath, presumably once neovim 0.9.5 is released.
  return (table.concat({ ... }, '/'):gsub('//+', '/'))
end

function M.path.relative_norm(path)
  return vim.fn.fnamemodify(path, ':~:.')
end

M.cursor = {}

---@class Position
---@field row number 0-indexed row
---@field col number 0-indexed column, can be vim.v.maxcol which means after end of line

---@class Span
---@field start Position
---@field stop Position

---@alias Selection Span

---@return Selection
function M.cursor.selection()
  -- NOTE These give the byte pos of column and not char pos
  -- also < and > only get updated after leaving visual mode
  -- https://www.reddit.com/r/neovim/comments/13mfta8/reliably_get_the_visual_selection_range/
  -- may want to switch to 'v' and '.' as key mappings from visual mode may not work if we don't
  -- leave visual mode first (most will though)
  local start = vim.fn.getpos("'<")
  local stop = vim.fn.getpos("'>")

  return {
    start = {
      row = start[2] - 1,
      col = start[3] - 1,
    },
    stop = {
      row = stop[2] - 1,
      col = stop[3], -- stop col can be vim.v.maxcol which means entire line
    },
  }
end

---@return Position
function M.cursor.position()
  local pos = vim.api.nvim_win_get_cursor(0)

  return {
    row = pos[1] - 1,
    col = pos[2],
  }
end

function M.cursor.place_with_keys(position)
  local keys = position.row + 1 .. 'G0'

  if position.col > 0 then
    keys = keys .. position.col .. 'l'
  end

  return keys
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

-- pos is between start and stop inclusive
function M.position.is_bounded(pos, start, stop)
  if pos.row < start.row then
    return false
  end

  if pos.row > stop.row then
    return false
  end

  if pos.row == start.row and pos.col < start.col then
    return false
  end

  if pos.row == stop.row and pos.col > stop.col then
    return false
  end

  return true
end

---@param pos Position
---@return Position
function M.position.row_below(pos)
  return {
    col = 0,
    row = pos.row + 1,
  }
end

--- Converts a 0-indexed position like {row = 0, col = 0} to '(0,0)'
---@param pos Position
---@return string
function M.position_string(pos)
  return string.format('(%s,%s)', pos.row, pos.col)
end

M.COL_ENTIRE_LINE = vim.v.maxcol or 2147483647

M.buf = {}

function M.buf.text(selection)
  local start_row = selection.start.row
  local start_col = selection.start.col

  if start_col == M.COL_ENTIRE_LINE then
    start_row = start_row + 1
    start_col = 0
  end

  local success, text = pcall(
    vim.api.nvim_buf_get_text,
    0,
    start_row,
    start_col,
    selection.stop.row,
    selection.stop.col == M.COL_ENTIRE_LINE and -1 or selection.stop.col,
    {}
  )

  if success then
    return text
  else
    return {}
  end
end

function M.buf.set_text(selection, lines)
  local stop_col = selection.stop.col == M.COL_ENTIRE_LINE
      and #assert(
        vim.api.nvim_buf_get_lines(
          0,
          selection.stop.row,
          selection.stop.row + 1,
          true
        )[1],
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

---@param callback fun(user_input: string, prompt_content: string)
---@param initial_content? string | string[]
---@param title? string
function M.buf.prompt(callback, initial_content, title)
  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'prompt')

  vim.cmd(':b ' .. bufnr)

  vim.api.nvim_set_option_value(
    'winbar',
    title or 'Prompt',
    { scope = 'local' }
  )

  if initial_content ~= nil then
    if type(initial_content) == 'string' then
      initial_content = vim.fn.split(initial_content, '\n')
    end
    vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, initial_content)
  end

  vim.fn.prompt_setcallback(bufnr, function(user_input)
    local buf_content =
      table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -3, false), '\n')
    local success, result = pcall(callback, user_input, buf_content)

    if not success then
      M.notify(result, vim.log.levels.ERROR)
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

M.text = {}

function M.text.build_line_offsets(content)
  local offsets = { 1 }
  local i = 1
  local len = #content
  while i <= len do
    local c = content:sub(i, i)
    if c == '\n' then
      table.insert(offsets, i + 1)
      i = i + 1
    elseif c == '\r' then
      if i + 1 <= len and content:sub(i + 1, i + 1) == '\n' then
        table.insert(offsets, i + 2)
        i = i + 2
      else
        table.insert(offsets, i + 1)
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return offsets
end

M.text.apply_edits = function(content, edits, match_fn)
  -- Build line offsets index
  local line_offsets = M.text.build_line_offsets(content)
  local total_lines = #line_offsets
  local processed_edits = {}

  -- Process each edit
  for i, edit in ipairs(edits) do
    -- Get search parameters from match function
    local search_string, start_line, plain = match_fn(edit)

    if type(search_string) ~= 'string' or search_string == '' then
      error('Edit ' .. i .. ' requires non-empty search string')
    end
    if type(edit.replacement_string) ~= 'string' then
      error('Edit ' .. i .. ' requires replacement_string')
    end
    if
      start_line ~= nil and (type(start_line) ~= 'number' or start_line < 1)
    then
      error('Edit ' .. i .. ' has invalid start_line')
    end

    -- Get start offset for this line
    start_line = start_line or 1
    if start_line > total_lines then
      error('Edit ' .. i .. ': start_line exceeds file length')
    end
    local start_offset = line_offsets[start_line]

    -- Find search string starting at the specified line
    local found_start, found_end =
      content:find(search_string, start_offset, plain)
    if not found_start then
      error(
        'Edit '
          .. i
          .. ': could not find search string starting at line '
          .. start_line
      )
    end

    table.insert(processed_edits, {
      start = found_start,
      finish = found_end,
      replacement_string = edit.replacement_string,
    })
  end

  -- Sort edits by start position
  table.sort(processed_edits, function(a, b)
    return a.start < b.start
  end)

  -- Check for overlapping edits
  for i = 2, #processed_edits do
    if processed_edits[i].start <= processed_edits[i - 1].finish then
      error(
        'Overlapping edits: edit ' .. i .. ' starts before previous edit ends'
      )
    end
  end

  -- Apply edits to create new content
  local parts = {}
  local last = 1
  for _, edit in ipairs(processed_edits) do
    table.insert(parts, content:sub(last, edit.start - 1))
    table.insert(parts, edit.replacement_string)
    last = edit.finish + 1
  end
  table.insert(parts, content:sub(last))
  return table.concat(parts)
end

return M
