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
      includeChats = {
        type = 'boolean',
        description = 'Also search chat history',
        default = false,
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
      if args.includeChats or not file:match('%.mchat$') then
        local lines = vim.fn.readfile(file)

        local results_in_file = {}
        local context_start = 1
        local in_context = false
        local last_match_line = 0

        for i, line in ipairs(lines) do
          local found = line:find(args.pattern, 1, args.plain)

          if found then
            if not in_context then
              -- Start new context (3 lines before match)
              context_start = math.max(1, i - 3)
              in_context = true
            end
            last_match_line = i
          end

          -- If we're in a context and either:
          -- 1. We're 3 lines past the last match
          -- 2. We're at the end of the file
          if in_context and ((i >= last_match_line + 3) or (i == #lines)) then
            -- End context (3 lines after last match)
            local context_end = math.min(#lines, last_match_line + 3)

            -- Collect context lines
            local context_lines = {}
            for j = context_start, context_end do
              table.insert(context_lines, lines[j])
            end

            -- Get line numbers of matches in this context
            local match_lines = {}
            for j = context_start, context_end do
              if lines[j]:find(args.pattern, 1, args.plain) then
                table.insert(match_lines, j)
              end
            end

            if #match_lines > 0 then
              table.insert(results_in_file, {
                file = file,
                text = table.concat(context_lines, '\n'),
                match_lines = match_lines,
                context_start = context_start,
                context_end = context_end,
              })
            end

            in_context = false
          end
        end

        -- Add all results from this file to main results
        for _, result in ipairs(results_in_file) do
          table.insert(results, {
            file = result.file,
            text = result.text,
            match_lines = result.match_lines,
            context_start = result.context_start,
            context_end = result.context_end,
          })
        end
      end
    end

    if #results == 0 then
      return 'No matches found for pattern: ' .. args.pattern
    end

    local output = {}
    for _, result in ipairs(results) do
      local range = {
        start = result.context_start,
        stop = result.context_end,
      }

      local file_content = files.format_file_content(
        result.file,
        vim.split(result.text, '\n'),
        nil,
        range
      )
      table.insert(output, file_content .. '\n')
    end

    return table.concat(output, '\n')
  end,
}
