local files = require('model.util.files')

return {
  description = 'Apply edits to a file and display a diff to the user to accept them by chunk. Difficult to use correctly since any deviation in the "original_string" field from what is on disk will cause the edit to fail. Avoid.',
  parameters = {
    type = 'object',
    properties = {
      path = {
        type = 'string',
        description = 'Path to the file to edit',
      },
      edits = {
        type = 'array',
        description = 'List of edits to apply. Edits are sorted by start and applied from top to bottom of the file. Each edit applies only to the original file. Edits are not applied on top of each other. Edits must not overlap.',
        items = {
          type = 'object',
          properties = {
            start_line = {
              type = 'integer',
              description = 'Line number (1-indexed) to start looking for original_string',
            },
            original_string = {
              type = 'string',
              description = 'The string to search for.',
            },
            replacement_string = {
              type = 'string',
              description = 'Replacement string (may be multiline)',
            },
            is_lua_pattern = {
              type = 'boolean',
              description = 'Set true to treat the original_string as a lua pattern. Defaults to false. Useful if the original string is easy to express as a lua pattern, for example: `<head>(.-)</head>` to replace all the content in the head tag.',
            },
          },
          required = { 'original_string', 'replacement_string' },
        },
      },
    },
    required = { 'path', 'edits' },
  },
  invoke = function(args)
    -- Validate inputs
    if type(args.path) ~= 'string' then
      error('Invalid path: must be a string')
    end
    if not files.is_file_within_cwd(args.path) then
      error('Path must be within current working directory')
    end

    if type(args.edits) ~= 'table' or #args.edits == 0 then
      error('Edits must be a non-empty array')
    end

    local content = files.read_file(args.path)
    local new_content = files.apply_edits(args.path, content, args.edits)

    files.show_diff(args.path, new_content)

    return string.format('Processed %d edits to %s', #args.edits, args.path)
  end,
}
