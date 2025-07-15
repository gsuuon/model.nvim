local files = require('model.util.files')
local util = require('model.util')
local tool_utils = require('model.util.tools')
local rpc = require('model.util.rpc')

return {
  description = [[
Rewrite the contents of a file. If modifying a single function, prefer edit_file_treesitter to avoid regenerating the entire fire.

Provide the complete, self-contained file expanded in it's entirety. This tool WILL NOT expand comments like 'the rest goes here'. Leaving comments like that will REPLACE the code that was there with ONLY a comment. This is INCREDIBLY frustrating for users. NEVER do that. ALWAYS provide the ENTIRE, COMPLETE, UNABRIDGED file.

Tool result is the final written file with project formatting applied and diagnostics included. Diagnostics may be stale.
]],
  parameters = {
    type = 'object',
    properties = {
      path = {
        type = 'string',
        description = 'Path of the file to rewrite.',
      },
      content = {
        type = 'string',
        description = 'The complete new content of the file. ALWAYS pass the _entire_ file contents. NEVER insert anything like "rest of the file here" in a comment, the comment will replace all the text and the user will end up with a broken file.',
      },
    },
    required = { 'path', 'content' },
  },
  invoke = function(args, callback)
    if type(args.path) ~= 'string' then
      error('Invalid path: must be a string')
    end

    if type(args.content) ~= 'string' then
      error('content must be a string')
    end

    files.get_file_and_diagnostics(args.path, 'Final saved file', callback)

    return function()
      -- no cancel
    end,
      'Getting rewritten file with diagnostics..'
  end,
  presentation = function()
    local content = ''
    local path = ''
    local bufnr = nil

    local did_finish_content = false

    return tool_utils.process_partial_tool_call({
      content = {
        part = function(part)
          content = content .. part

          local text = util.json.decode('"' .. content .. '"')

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

          did_finish_content = true
        end,
      },
      path = {
        part = function(part)
          path = path .. part
        end,
        complete = function()
          files.show_diff(path, content, function(data)
            bufnr = data.new_bufnr

            if did_finish_content then
              vim.api.nvim_buf_set_lines(
                bufnr,
                0,
                -1,
                false,
                vim.split(content, '\n')
              )
              vim.api.nvim_buf_set_name(bufnr, 'rewrite_file done - ' .. path)
            else
              vim.api.nvim_buf_set_name(
                bufnr,
                'rewrite_file pending - ' .. path
              )
            end

            rpc.notify(
              'rewrite_file',
              vim.tbl_deep_extend('force', data, { action = 'open' })
            )
          end)
        end,
      },
    })
  end,

  -- autoaccept side effects of presentation
  presentation_autoaccept = function(args, done)
    local arguments, err = util.json.decode(args)
    if arguments then
      -- Iterate over all tabpages to find the one with the diff pair
      local found = false
      for _, tabpagenr in ipairs(vim.api.nvim_list_tabpages()) do
        local ok, diff_pair =
          pcall(vim.api.nvim_tabpage_get_var, tabpagenr, 'model_nvim_diff_pair')
        if ok and diff_pair and diff_pair.path == arguments.path then
          found = true
          -- Apply changes to the original buffer
          vim.api.nvim_win_call(diff_pair.orig_win, function()
            vim.cmd('1,$+1diffget')
            vim.cmd('write')
            vim.cmd('q')
            util.show('Autoaccept saved: ' .. arguments.path)
          end)

          -- Close the diff buffer
          vim.api.nvim_win_call(diff_pair.new_win, function()
            vim.cmd('q')
          end)

          break
        end
      end

      if not found then
        util.eshow('Failed to find rewrite_file temporary buffer')
      end

      done()
    else
      util.eshow('Failed to parse arguments: ' .. err)
    end
  end,
}
