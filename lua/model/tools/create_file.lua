local util = require('model.util')
local files = require('model.util.files')

local function path_is_absolute(path)
  -- cross-platform (windows, unix) check that path is relative
  return path:match('^/') or path:match('^%a:[/\\]')
end

local function path_is_above_cwd(path)
  -- normalize path and check if it contains parent directory references
  local normalized = vim.fs.normalize(path)
  return normalized:match('%.%./')
    or normalized:match('^%.%./')
    or normalized:match('/%.%./')
end

return {
  description = 'Create a new file with given content',
  parameters = {
    type = 'object',
    properties = {
      path = {
        type = 'string',
        description = 'Relative path to the file',
      },
      content = {
        type = 'string',
        description = 'Content to write to the file',
      },
    },
    required = { 'path', 'content' },
  },
  invoke = function(args, callback)
    if type(args.path) ~= 'string' then
      error('Invalid path: must be a string')
    end

    if path_is_absolute(args.path) then
      error('Path must be relative')
    end

    if path_is_above_cwd(args.path) then
      error('Path must resolve to within cwd')
    end

    local dir = vim.fs.dirname(args.path)
    if dir and dir ~= '' then
      local success = vim.fn.mkdir(dir, 'p')
      if success == 0 then
        error('Failed to create directory: ' .. dir)
      end
    end

    local already_existed = vim.fn.filereadable(args.path) == 1

    -- Create a new buffer and set its content
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(
      bufnr,
      0,
      -1,
      false,
      vim.split(args.content, '\n')
    )
    vim.api.nvim_buf_set_name(bufnr, args.path)
    vim.api.nvim_buf_set_option(
      bufnr,
      'filetype',
      vim.filetype.match({ filename = args.path }) or ''
    )

    -- Display a message
    if already_existed then
      util.show('Creating file that already exists: ' .. args.path)
    else
      util.show('Opened buffer for new file: ' .. args.path)
    end

    local latest_content = nil

    local function handle_exit()
      if latest_content then
        callback(latest_content)
      else
        callback(nil, 'Buffer exited without saving')
      end
    end

    -- Update latest_content on each write
    vim.api.nvim_create_autocmd('BufWritePost', {
      buffer = bufnr,
      callback = function()
        latest_content = files.yank_with_line_numbers_and_filename()
      end,
    })

    -- Handle buffer unload (call callback with latest saved content or error)
    vim.api.nvim_create_autocmd('BufLeave', {
      buffer = bufnr,
      once = true,
      callback = handle_exit,
    })

    -- Schedule opening the buffer in a new tab
    vim.schedule(function()
      vim.cmd('tabnew')
      vim.api.nvim_set_current_buf(bufnr)
    end)

    return function()
      -- Cancel function (no-op since we can't cancel the scheduled operation)
    end
  end,
}
