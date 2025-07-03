return {
  description = 'Get the contents of a buffer by name or number, optionally specifying a line range',
  parameters = {
    type = 'object',
    properties = {
      buffer = {
        type = { 'string', 'number' },
        description = 'Buffer name or number',
      },
      start = {
        type = 'number',
        description = 'Optional starting line number (1-indexed). If not provided, defaults to the first line.',
      },
      stop = {
        type = 'number',
        description = 'Optional ending line number (1-indexed). If not provided, defaults to the last line.',
      },
    },
    required = { 'buffer' },
  },
  invoke = function(args)
    local buf
    if type(args.buffer) == 'number' then
      buf = args.buffer
      if not buf then
        error('Buffer not found: ' .. args.buffer)
      end
    else
      buf = vim.fn.bufnr(args.buffer)
      if buf == -1 then
        error('Buffer not found: ' .. args.buffer)
      end
    end

    if not vim.api.nvim_buf_is_loaded(buf) then
      error('Buffer is not loaded: ' .. args.buffer)
    end

    local start_line = args.start and args.start - 1 or 0 -- Convert to 0-indexed
    local end_line = args.stop and args.stop - 1 or -1 -- -1 means last line

    local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)
    return table.concat(lines, '\n')
  end,
}
