local files = require('model.util.files')
local util = require('model.util')
local tool_utils = require('model.util.tools')

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

    if type(args.new_content) ~= 'string' then
      error('new_content must be a string')
    end

    files.get_file_and_diagnostics(args.path, 'Final saved file', callback)

    return function()
      -- no cancel
    end,
      'Getting rewritten file with diagnostics..'
  end,
  presentation = function()
    local new_content = ''
    local path = ''
    local bufnr = nil

    return tool_utils.process_partial_tool_call({
      new_content = {
        part = function(part)
          new_content = new_content .. part

          local text = util.json.decode('"' .. new_content .. '"')

          if text then
            if bufnr then
              vim.api.nvim_buf_set_lines(
                bufnr,
                0,
                -1,
                false,
                vim.split(text, '\n')
              )
            end
          end
        end,
        complete = function()
          if bufnr then
            vim.api.nvim_buf_set_name(bufnr, 'rewrite_file done - ' .. path)
          else
            if path == '' then
              util.show('Received all content')
            else
              util.show('Received all content for ' .. path)
            end
          end
        end,
      },
      path = {
        part = function(part)
          path = path .. part
        end,
        complete = function()
          files.show_diff(path, new_content, function(_, new_bufnr)
            bufnr = new_bufnr

            -- TODO set name can error if that name is already taken
            vim.api.nvim_buf_set_name(bufnr, 'rewrite_file pending - ' .. path)
          end)
        end,
      },
    })
  end,
}
