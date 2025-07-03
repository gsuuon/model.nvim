local files = require('model.util.files')

return {
  description = "Read a file's contents",
  parameters = {
    type = 'object',
    properties = {
      path = {
        type = 'string',
        description = 'Absolute or relative path to the file',
      },
    },
    required = { 'path' },
  },
  invoke = function(args)
    if type(args.path) ~= 'string' then
      error('Invalid path: must be a string')
    end

    if not files.is_file_within_cwd(args.path) then
      error(
        'File must exist and be within current working directory: ' .. args.path
      )
    end

    return files.read_file(args.path)
  end,
}
