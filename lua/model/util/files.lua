local util = require('model.util')

local function start_lsp_servers(bufnr)
  local lsp_util = require('lspconfig.util')

  local count = 0

  vim.api.nvim_buf_call(bufnr, function()
    local matching_configs = lsp_util.get_config_by_ft(vim.bo.filetype)
    for _, config in ipairs(matching_configs) do
      config.launch()
      count = count + 1
    end
  end)

  return count
end

local function find_max_backticks(lines)
  local max_backticks = 0
  for _, line in ipairs(lines) do
    local line_backticks = line:match('```+')
    if line_backticks then
      max_backticks = math.max(max_backticks, #line_backticks)
    end
  end
  return max_backticks
end

local function format_file_content(filename, lines, range)
  local file_info = 'File: `' .. filename .. '`\n'

  -- Count maximum number of consecutive backticks in file content
  local max_backticks = find_max_backticks(lines)

  -- Determine fence length (minimum 3, one more than max found)
  local fence_length = math.max(3, max_backticks + 1)
  local fence = string.rep('`', fence_length)

  file_info = file_info .. fence
  local filetype = vim.fn.fnamemodify(filename, ':e')
  if filetype and filetype ~= '' then
    file_info = file_info .. ' ' .. filetype
  end
  file_info = file_info .. '\n'

  if range then
    filename = filename .. '#L' .. range.start .. '-L' .. range.stop
  end

  return file_info .. table.concat(lines, '\n') .. '\n' .. fence
end

local function format_diagnostics(diagnostics)
  if #diagnostics == 0 then
    return ''
  end

  local lines = { '\nDiagnostics:\n' }
  for _, d in ipairs(diagnostics) do
    local severity = vim.diagnostic.severity[d.severity]
    table.insert(
      lines,
      string.format('[%s] L%d: %s', severity, d.lnum + 1, d.message)
    )
  end

  -- Count maximum number of consecutive backticks in diagnostic lines
  local max_backticks = find_max_backticks(lines)

  -- Determine fence length (minimum 3, one more than max found)
  local fence_length = math.max(3, max_backticks + 1)
  local fence = string.rep('`', fence_length)

  table.insert(lines, 2, fence) -- Insert fence after "Diagnostics:"
  table.insert(lines, fence) -- Add closing fence

  return table.concat(lines, '\n')
end

local function get_buffer_content_and_diagnostics(range, callback)
  local buf_name = vim.fn.expand('%')
  local filename = buf_name ~= '' and util.path.relative_norm(buf_name)
    or '[No Name]'

  local lines
  if range == nil then
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  else
    lines = vim.api.nvim_buf_get_lines(0, range.start - 1, range.stop, false)
  end

  local file_content = format_file_content(filename, lines, range)
  local diagnostics

  if range == nil then
    diagnostics = vim.diagnostic.get(0)
  else
    local start_zero_idx = range.start - 1
    local stop_zero_idx = range.stop - 1
    diagnostics = vim.tbl_filter(function(d)
      local lnum = d.lnum
      return lnum >= start_zero_idx and lnum <= stop_zero_idx
    end, vim.diagnostic.get(0))
  end

  local diagnostic_content = format_diagnostics(diagnostics)
  local result = file_content .. diagnostic_content

  if callback then
    callback(result)
  else
    return result
  end
end

local function yank_with_line_numbers_and_filename(register, range)
  register = register or '"'
  local result = get_buffer_content_and_diagnostics(range)
  vim.fn.setreg(register, result)
  return result
end

local function get_file_and_diagnostics(filepath, callback)
  local bufnr = vim.fn.bufadd(filepath)
  if not vim.loop.fs_stat(filepath) then
    error('File does not exist: ' .. filepath)
  end

  if bufnr == 0 then
    util.eshow('Failed to bufadd')
    error('Failed to bufadd: ' .. filepath)
  end

  local was_loaded = vim.fn.bufloaded(bufnr) == 1

  vim.fn.bufload(bufnr)

  local started_servers = start_lsp_servers(bufnr)

  local diagnostics_listener = nil
  local timeout = nil

  local function return_file_only()
    if diagnostics_listener then
      vim.api.nvim_del_autocmd(diagnostics_listener)
    end

    -- Format the file content without diagnostics
    local buf_name = vim.fn.bufname(bufnr)
    local filename = buf_name ~= '' and util.path.relative_norm(buf_name)
      or '[No Name]'
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local result = format_file_content(filename, lines, nil)

    if not was_loaded then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end

    callback(result)
  end

  local function return_file_and_diagnostics()
    local diagnostics = vim.diagnostic.get(bufnr)

    if timeout then
      timeout:stop()
    end

    -- Format the diagnostics and file content
    local buf_name = vim.fn.bufname(bufnr)
    local filename = buf_name ~= '' and util.path.relative_norm(buf_name)
      or '[No Name]'
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local file_content = format_file_content(filename, lines, nil)
    local diagnostic_content = format_diagnostics(diagnostics)
    local result = file_content .. diagnostic_content

    if diagnostics_listener then
      vim.api.nvim_del_autocmd(diagnostics_listener)
    end

    if not was_loaded then
      vim.api.nvim_buf_delete(bufnr, { force = true, unload = true })
    end

    callback(result)
  end

  if started_servers == 0 then
    vim.schedule(return_file_only)
  else
    timeout = vim.defer_fn(return_file_only, 10000) -- 10 second timeout
    local diagnostics = vim.diagnostic.get(bufnr)
    if #diagnostics > 0 then
      -- It already had diagnostics
      vim.schedule(return_file_and_diagnostics)
    else
      vim.schedule(function()
        diagnostics_listener =
          vim.api.nvim_create_autocmd('DiagnosticChanged', {
            buffer = bufnr,
            callback = function()
              return_file_and_diagnostics()
            end,
          })
      end)
    end
  end
end

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

local function show_diff(original_name, updated, on_show)
  vim.schedule(function()
    vim.cmd('tabnew')
    vim.cmd('set diffopt+=vertical')
    vim.cmd('set buftype=nofile')
    vim.cmd('set bufhidden=wipe')
    vim.cmd('set nobuflisted')

    local bufname = 'diff - ' .. original_name
    local i = 1
    while vim.fn.bufexists(bufname) ~= 0 do
      bufname = 'diff - ' .. i .. ' - ' .. original_name
      i = i + 1
    end

    vim.cmd('file ' .. vim.fn.fnameescape(bufname))

    local new_bufnr = vim.api.nvim_get_current_buf()

    local lines = vim.split(updated, '\n', { plain = true })
    if lines[#lines] == '' and updated:sub(-1) == '\n' then
      table.remove(lines)
    end

    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.keymap.set('n', '<tab>', 'dp]c', { buffer = true, nowait = true })

    vim.cmd('diffsplit ' .. vim.fn.fnameescape(original_name))
    local orig_ft = vim.api.nvim_buf_get_option(0, 'filetype')

    vim.api.nvim_buf_set_option(new_bufnr, 'filetype', orig_ft)

    vim.cmd('wincmd h') -- Focus on the new version

    if on_show then
      on_show(orig_bufnr, new_bufnr)
    end
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
  yank_with_line_numbers_and_filename = yank_with_line_numbers_and_filename,
  get_file_and_diagnostics = get_file_and_diagnostics,
  format_file_content = format_file_content,
  format_diagnostics = format_diagnostics,
}
