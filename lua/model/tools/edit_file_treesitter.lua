local treesitter = require('model.util.treesitter')
local files = require('model.util.files')
local util = require('model.util')
local json_parse = require('model.util.json_stream_parse')
local segment = require('model.util.segment')

return {
  description = [[
Edit a file by replacing the contents of a tree-sitter node. First use get_file_treesitter to identify nodes.
]],
  parameters = {
    type = 'object',
    properties = {
      path = {
        type = 'string',
        description = 'Path of the file to edit.',
      },
      node_name = {
        type = 'string',
        description = 'Tree-sitter node type name to match',
      },
      contains = {
        type = 'string',
        description = 'First line of text the node must contain',
      },
      content = {
        type = 'string',
        description = 'Complete content to replace the node. If the node has documentation comment nodes before it, they will also be replaced with this content. Include any desired documentation comments in the content.',
      },
    },
    required = { 'path', 'node_name', 'contains', 'content' },
  },
  invoke = function(args, callback)
    files.get_file_and_diagnostics(
      args.path,
      'Edited file with tree-sitter nodes',
      callback
    )
    return function() end, 'Collected edit results'
  end,
  presentation = function()
    local bufnr = nil
    local path = ''
    local pending_edit = nil
    local seg = nil

    local function apply_edit(edit)
      if not bufnr then
        pending_edit = edit
        return
      end

      local range = treesitter.get_node_range(bufnr, {
        name = edit.node_name,
        contains = edit.contains,
        doc_comments = true,
      })

      if not range then
        util.eshow(
          string.format(
            'Node not found: %s containing "%s"',
            edit.node_name,
            edit.contains
          )
        )
        return
      end

      vim.api.nvim_buf_set_text(
        bufnr,
        range.start.row,
        range.start.col,
        range.stop.row,
        range.stop.col,
        {}
      )

      seg = segment.create_segment_at(range.start.row, range.start.col)

      if edit.content then
        seg.set_text(edit.content)
      end

      return seg
    end

    -- State for JSON parsing
    local parser = json_parse.object({
      path = json_parse.string(function(_, complete)
        if complete then
          path = complete
          files.show_diff(path, '', function(data)
            bufnr = data.new_bufnr
            vim.api.nvim_buf_set_name(bufnr, 'edit_file_treesitter - ' .. path)

            local orig_lines =
              vim.api.nvim_buf_get_lines(data.orig_bufnr, 0, -1, false)
            vim.api.nvim_buf_set_lines(data.new_bufnr, 0, -1, false, orig_lines)

            if pending_edit then
              apply_edit(pending_edit)
              pending_edit = nil
            end
          end)
        end
      end),
      node_name = json_parse.string(function(_, complete)
        if complete then
          pending_edit = pending_edit or {}
          pending_edit.node_name = complete
          if pending_edit.contains then
            apply_edit(pending_edit)
          end
        end
      end),
      contains = json_parse.string(function(_, complete)
        if complete then
          pending_edit = pending_edit or {}
          pending_edit.contains = complete
          if pending_edit.node_name then
            apply_edit(pending_edit)
          end
        end
      end),
      content = json_parse.string(function(part, complete)
        if complete then
          pending_edit = pending_edit or {}
          pending_edit.content = complete
          if seg then
            seg.set_text(complete)
            seg.clear_hl()
          end
        else
          pending_edit = pending_edit or {}
          pending_edit.content = (pending_edit.content or '') .. part
          if seg then
            seg.set_text(pending_edit.content)
          end
        end
      end),
    })

    return parser
  end,
  presentation_autoaccept = function(args, done)
    local arguments, err = util.json.decode(args)
    if not arguments then
      util.eshow('Failed to parse arguments: ' .. err)
      return done()
    end

    local found = false
    for _, tabpagenr in ipairs(vim.api.nvim_list_tabpages()) do
      local ok, diff_pair =
        pcall(vim.api.nvim_tabpage_get_var, tabpagenr, 'model_nvim_diff_pair')
      if ok and diff_pair and diff_pair.path == arguments.path then
        found = true
        vim.api.nvim_win_call(diff_pair.orig_win, function()
          vim.cmd('1,$+1diffget')
          vim.cmd('write')
          vim.cmd('q')
          util.show('Autoaccept saved: ' .. arguments.path)
        end)
        vim.api.nvim_win_call(diff_pair.new_win, function()
          vim.cmd('q')
        end)
        break
      end
    end

    if not found then
      util.eshow('Failed to find temporary buffer for ' .. arguments.path)
    end

    done()
  end,
}
