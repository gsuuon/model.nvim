local files = require('model.util.files')

-- List all files in git repo with git ls-files .
return {
  description = 'List files in git repository',
  parameters = {
    type = 'object',
    properties = {
      path = {
        type = 'string',
        description = 'Path to git repository (default: current directory)',
        default = '.',
      },
    },
    required = {},
  },
  invoke = function(args)
    local path = args.path or '.'
    if not files.is_file_within_cwd(path) then
      return nil, 'Path must be within current working directory'
    end

    return table.concat(files.list_files(path), '\n')
  end,
}
