--- Gets the tree-sitter tree's top level nodes for a buffer
---@param bufnr? number buffer number (defaults to current buffer)
---@param excludes? string[] optional list of node types to exclude (e.g. {'comment'})
---@return SimpleNode[] table of top level nodes with name, line and text
local function top_level_nodes(bufnr, excludes)
  bufnr = bufnr or vim.fn.bufnr()
  excludes = excludes or {}

  -- get the parser for the buffer's filetype
  local parser = vim.treesitter.get_parser(bufnr)
  -- get the syntax tree
  local tree = parser:parse()[1]
  -- get the root node
  local root = tree:root()

  -- collect top level nodes with first line content
  local nodes = {}
  for child in root:iter_children() do
    if child:named() then
      local node_type = child:type()
      -- skip excluded node types
      if not vim.tbl_contains(excludes, node_type) then
        local start_line = child:start()
        local first_line = vim.api.nvim_buf_get_lines(
          bufnr,
          start_line,
          start_line + 1,
          false
        )[1]

        table.insert(nodes, {
          name = node_type,
          line = start_line + 1, -- convert from 0-based to 1-based
          text = first_line,
        })
      end
    end
  end

  return nodes
end

---@class SimpleNode
---@field name string the node type name
---@field text string the first line of text in the node
---@field line number the 1-based line number where node starts

---@class SimpleNodeEdit
---@field name string the node type name
---@field contains string find node where first line contains this
---@field contents string contents to replace

---@class SimpleNodeCriteria
---@field name string the node type name
---@field contains string find node where first line contains this
---@field doc_comments? boolean also include contiguous nodes above the target containing 'comment' in type name

--- Gets the range of a node matching the given criteria
---@param bufnr integer buffer number
---@param criteria SimpleNodeCriteria
---@return Span? range of the node, or nil if not found
local function get_node_range(bufnr, criteria)
  local parser = vim.treesitter.get_parser(bufnr)
  local tree = parser:parse()[1]
  local root = tree:root()

  for child in root:iter_children() do
    if child:named() and child:type() == criteria.name then
      local start_row, start_col, end_row, end_col = child:range()
      local node_text_first_line = vim.api.nvim_buf_get_text(
        bufnr,
        start_row,
        start_col,
        end_row,
        end_col,
        {}
      )[1]

      if string.find(node_text_first_line, criteria.contains, 1, true) then
        -- Handle doc comments if requested
        if criteria.doc_comments then
          local prev = child:prev_named_sibling()
          local doc_start_row = start_row
          local doc_start_col = 0 -- Start at beginning of line for comments

          -- Walk backwards through contiguous comment nodes
          while
            prev
            and prev:named()
            and string.find(prev:type():lower(), 'comment', 1, true)
          do
            dshow({
              type = prev:type(),
              range = { prev:range() },
            })

            local prev_start_row = prev:start()

            -- Check if there's a gap between this comment and the previous node
            local lines_between = vim.api.nvim_buf_get_lines(
              bufnr,
              prev_start_row,
              doc_start_row,
              false
            )

            -- If there are any non-empty lines between, stop collecting
            local has_gap = false
            for _, line in ipairs(lines_between) do
              if line:match('^%s*$') then
                has_gap = true
                dshow('gap')
                break
              end
            end

            if has_gap then
              break
            end

            doc_start_row = prev_start_row
            prev = prev:prev_named_sibling()
          end

          return {
            start = {
              row = doc_start_row,
              col = doc_start_col,
            },
            stop = {
              row = end_row,
              col = end_col,
            },
          }
        else
          return {
            start = {
              row = start_row,
              col = start_col,
            },
            stop = {
              row = end_row,
              col = end_col,
            },
          }
        end
      end
    end
  end
  return nil
end

--- Replaces a node in the buffer with new content
---@param bufnr integer buffer number
---@param edit SimpleNodeEdit
---@return boolean success whether the replacement was successful
local function replace_node(bufnr, edit)
  local criteria = {
    name = edit.name,
    contains = edit.contains,
  }
  local range = get_node_range(bufnr, criteria)
  if not range then
    return false
  end

  vim.api.nvim_buf_set_text(
    bufnr,
    range.start.row,
    range.start.col,
    range.stop.row,
    range.stop.col,
    vim.split(edit.contents, '\n')
  )
  return true
end

--- TODO deduplicate with files util -- add something like with_file that gives us a temp buffer to work with or uses existing
local function file_top_level_nodes(filename, excludes)
  local bufnr = vim.fn.bufadd(filename)
  local was_loaded = vim.fn.bufloaded(bufnr) == 1

  if not vim.loop.fs_stat(filename) then
    error('File does not exist: ' .. filename)
  end

  if bufnr == 0 then
    error('Failed to bufadd: ' .. filename)
  end

  vim.fn.bufload(bufnr)
  local nodes = top_level_nodes(bufnr, excludes)

  if not was_loaded then
    vim.api.nvim_buf_delete(bufnr, { force = true, unload = true })
  end

  return nodes
end

return {
  top_level_nodes = top_level_nodes,
  get_node_range = get_node_range,
  replace_node = replace_node,
  file_top_level_nodes = file_top_level_nodes,
}
