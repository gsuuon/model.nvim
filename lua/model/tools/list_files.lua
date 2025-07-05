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

    return table.concat(files.list_files(path), '\n')
  end,
}
