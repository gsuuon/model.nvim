local files = require('model.util.files')

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
  invoke = function(args, callback)
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

    files.show_diff(args.path, args.new_content, function(original_bufnr)
      -- like in create_file, we want to call callback with actual saved disk contents extracted by files.yank_with_line_numbers_and_filename
      local latest_content = nil

      local function handle_exit()
        if latest_content then
          callback(latest_content)
        else
          callback(nil, 'Buffer exited without saving')
        end
      end

      -- Update latest_content on each write
      vim.api.nvim_create_autocmd('BufWritePost', {
        buffer = original_bufnr,
        callback = function()
          latest_content = files.yank_with_line_numbers_and_filename()
        end,
      })

      -- Handle buffer unload (call callback with latest saved content or error)
      vim.api.nvim_create_autocmd('BufLeave', {
        buffer = original_bufnr,
        once = true,
        callback = handle_exit,
      })
    end)

    return function() end
  end,
}
