local util = require('model.util')

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
  invoke = function(args)
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

    -- Schedule the buffer operations to run in the main thread
    vim.schedule(function()
      -- Open a new tab
      vim.cmd('tabnew')

      -- Create a new buffer and set its content
      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(args.content, '\n'))

      -- Set the buffer's file name and filetype
      vim.api.nvim_buf_set_name(0, args.path)
      vim.api.nvim_buf_set_option(
        0,
        'filetype',
        vim.filetype.match({ filename = args.path }) or ''
      )

      -- Display a message
      if already_existed then
        util.show('Creating file that already exists: ' .. args.path)
      else
        util.show('Opened buffer for new file: ' .. args.path)
      end
    end)

    return 'Created file: ' .. args.path
  end,
}
