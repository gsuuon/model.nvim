local files = require('model.util.files')

-- Git tool for basic Git operations
return {
  description = 'Execute Git commands',
  parameters = {
    type = 'object',
    properties = {
      command = {
        type = 'string',
        description = 'Git command to execute (e.g., "status", "log", "diff")',
      },
    },
    required = { 'command' },
  },
  invoke = function(args)
    local path = args.path or '.'

    if not files.is_file_within_cwd(path) then
      error('Path must be within current working directory')
    end

    local cmd = 'git ' .. args.command
    local output = vim.fn.system(cmd)
    local exit_code = vim.v.shell_error

    if exit_code ~= 0 then
      return nil,
        'Git command failed with exit code ' .. exit_code .. ': ' .. output
    end
    return output
  end,
}
