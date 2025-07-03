local files = require('model.util.files')

local function run_edit(args)
  if type(args.path) ~= 'string' then
    error('Invalid path: must be a string')
  end
  if not files.is_file_within_cwd(args.path) then
    error(
      'File must exist and be within current working directory: ' .. args.path
    )
  end
  if type(args.new_content) ~= 'string' then
    error('new_content must be a string')
  end

  files.show_diff(args.path, args.new_content)

  return string.format('Showed diff for %s', args.path)
end

return {
  description = 'Show a diff between the current file and a proposed new version, allowing the user to accept changes by chunk.',
  parameters = {
    type = 'object',
    properties = {
      path = {
        type = 'string',
        description = 'Path to the file to edit',
      },
      new_content = {
        type = 'string',
        description = 'The complete new content of the file',
      },
    },
    required = { 'path', 'new_content' },
  },
  invoke = function(args)
    if #args > 0 then
      -- a list
      -- not yet documented but sometimes this hallucination happens
      return vim.tbl_map(run_edit, args)
    else
      return run_edit(args)
    end
  end,
}
