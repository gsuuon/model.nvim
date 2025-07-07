local files = require('model.util.files')

return {
  description = 'Search for a pattern in files within the repository. Uses Lua string patterns by default for efficient matching. Optionally, exact string matching can be enabled.',
  parameters = {
    type = 'object',
    properties = {
      pattern = {
        type = 'string',
        description = 'The pattern to search for. Uses Lua patterns by default.',
      },
      plain = {
        type = 'boolean',
        description = 'Set to true for exact string matching. Defaults to false (Lua pattern matching).',
        default = false,
      },
      path = {
        type = 'string',
        description = 'Path to the repository or directory to search. Defaults to the current working directory.',
        default = '.',
      },
    },
    required = { 'pattern' },
  },
  invoke = function(args)
    -- Validate inputs
    if type(args.pattern) ~= 'string' or args.pattern == '' then
      error('Invalid pattern: must be a non-empty string')
    end

    -- Ensure the path is within the current working directory
    local search_path = args.path or '.'
    if not files.is_file_within_cwd(search_path) then
      error('Path must be within current working directory')
    end

    -- List all files in the repository
    local dir_files = files.list_files(search_path)
    if #dir_files == 0 then
      return 'No files found in the repository.'
    end

    local results = {}

    -- Search each file for the pattern
    for _, file in ipairs(dir_files) do
      local content = files.read_file(file)
      local found_start, found_end = content:find(args.pattern, 1, args.plain)

      if found_start then
        -- Get surrounding context (50 chars before and after)
        local context_start = math.max(1, found_start - 50)
        local context_end = math.min(#content, found_end + 50)
        local context = content:sub(context_start, context_end)

        table.insert(results, {
          file = file,
          text = context,
          start = found_start,
          finish = found_end,
        })
      else
      end
    end

    if #results == 0 then
      return 'No matches found for pattern: ' .. args.pattern
    end

    local output = {}
    for _, result in ipairs(results) do
      table.insert(
        output,
        string.format(
          'File: %s\nLines: %d-%d\nContext:\n```%s\n%s\n```\n',
          result.file,
          result.start,
          result.finish,
          vim.fn.fnamemodify(result.file, ':e'),
          result.text
        )
      )
    end

    return table.concat(output, '\n')
  end,
}
