local function is_file_within_cwd(path)
  if not path or path == '' then
    return false
  end

  local cwd = vim.loop.cwd()
  local real_cwd = vim.loop.fs_realpath(cwd) or cwd
  local real_path = vim.loop.fs_realpath(path) or path

  if not real_path then
    return false
  end

  -- Normalize paths for comparison
  real_cwd = vim.fs.normalize(real_cwd)
  real_path = vim.fs.normalize(real_path)

  return real_path == real_cwd or real_path:find(real_cwd, 1, true) == 1
end

local function write_file(path, content)
  local file = io.open(path, 'wb')
  if not file then
    return false, 'Failed to open file: ' .. path
  end

  local success, err = pcall(function()
    file:write(content)
    file:close()
  end)

  if not success then
    file:close()
    return false, err
  end

  return true
end

local function read_file(path)
  local file, err = io.open(path, 'r')
  if not file then
    error('File error: ' .. (err or 'unknown'))
  end

  local content = file:read('*a')
  file:close()

  return content
end

local function list_files(path)
  local files =
    vim.fn.systemlist('git ls-files -c -o --exclude-standard ' .. path)

  -- Filter out deleted files (check if they exist on disk)
  local existing_files = {}
  for _, file in ipairs(files) do
    if vim.loop.fs_stat(file) then
      table.insert(existing_files, file)
    end
  end

  return existing_files
end

-- Helper to build an index of line start offsets
local function build_line_offsets(content)
  local offsets = { 1 }
  local i = 1
  local len = #content

  while i <= len do
    if content:sub(i, i) == '\r' and content:sub(i + 1, i + 1) == '\n' then
      table.insert(offsets, i + 2)
      i = i + 2
    elseif content:sub(i, i) == '\n' then
      table.insert(offsets, i + 1)
      i = i + 1
    else
      i = i + 1
    end
  end
  return offsets
end

local function apply_edits(filename, content, edit_requests)
  -- currently if any edits fail, all edits fail
  local line_offsets = build_line_offsets(content)
  local total_lines = #line_offsets
  local edits = {}

  -- Process each edit
  for i, edit in ipairs(edit_requests) do
    if type(edit) ~= 'table' then
      error('Edit ' .. i .. ' must be a table')
    end
    if
      edit.start_line ~= nil
      and (type(edit.start_line) ~= 'number' or edit.start_line < 1)
    then
      error('Edit ' .. i .. ' has invalid start_line')
    end
    if type(edit.original_string) ~= 'string' or edit.original_string == '' then
      error('Edit ' .. i .. ' requires non-empty original_string')
    end
    if type(edit.replacement_string) ~= 'string' then
      error('Edit ' .. i .. ' requires replacement_string')
    end

    -- Get start offset for this line
    local start_line = edit.start_line or 1
    if start_line > total_lines then
      error('Edit ' .. i .. ': start_line exceeds file length')
    end
    local start_offset = line_offsets[start_line]

    -- Find original_string starting at the specified line
    local found_start, found_end
    do
      if edit.is_lua_pattern then
        found_start, found_end =
          content:find(edit.original_string, start_offset)
      else
        found_start, found_end =
          content:find(edit.original_string, start_offset, true)
      end
    end

    if not found_start then
      error(
        'Edit '
          .. i
          .. ': could not find original_string "'
          .. edit.original_string
          .. '" starting at line '
          .. start_line
          .. ' (offset '
          .. start_offset
          .. ')'
          .. ' in file '
          .. filename
      )
    end

    table.insert(edits, {
      start = found_start,
      finish = found_end,
      replacement_string = edit.replacement_string,
    })
  end

  -- Sort edits by start position
  table.sort(edits, function(a, b)
    return a.start < b.start
  end)

  -- Check for overlapping edits
  for i = 2, #edits do
    if edits[i].start <= edits[i - 1].finish then
      error(
        'Overlapping edits: edit ' .. i .. ' starts before previous edit ends'
      )
    end
  end

  -- Apply edits to create new content
  local parts = {}
  local last = 1
  for _, edit in ipairs(edits) do
    table.insert(parts, content:sub(last, edit.start - 1))
    table.insert(parts, edit.replacement_string)
    last = edit.finish + 1
  end
  table.insert(parts, content:sub(last))

  return table.concat(parts)
end

local function show_diff(original_name, updated)
  vim.schedule(function()
    vim.cmd('tabnew')
    vim.cmd('set diffopt+=vertical')
    vim.cmd('set buftype=nofile')
    vim.cmd('set bufhidden=wipe')
    vim.cmd('set nobuflisted')

    local bufname = '[Diff] ' .. original_name
    local i = 1
    while vim.fn.bufexists(bufname) ~= 0 do
      bufname = '[Diff] ' .. i .. ' ' .. original_name
      i = i + 1
    end
    vim.cmd('file ' .. vim.fn.fnameescape(bufname))

    local lines = vim.split(updated, '\n', { plain = true })
    if lines[#lines] == '' and updated:sub(-1) == '\n' then
      table.remove(lines)
    end

    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.keymap.set('n', '<tab>', 'dp]c', { buffer = true, nowait = true })

    vim.cmd('diffsplit ' .. vim.fn.fnameescape(original_name))
    vim.cmd('wincmd h') -- Focus on the new version
  end)
end

return {
  list_files = list_files,
  read_file = read_file,
  is_file_within_cwd = is_file_within_cwd,
  write_file = write_file,
  build_line_offsets = build_line_offsets,
  apply_edits = apply_edits,
  show_diff = show_diff,
}
