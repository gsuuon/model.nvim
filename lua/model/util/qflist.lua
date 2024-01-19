local util = require('model.util')

local function add()
  local filename = vim.fn.bufname()

  local already_added = vim.tbl_contains(
    vim.fn.getqflist() or {},
    function(item)
      return vim.fn.bufname(item.bufnr) == filename
    end,
    {predicate = true}
  )

  if not already_added then
    vim.fn.setqflist({{filename=filename, text='model.nvim context'}}, 'a')
  end
end

local function remove()
  local filename = vim.fn.bufname()

  vim.fn.setqflist(
    vim.tbl_filter(function(item)
      return vim.fn.bufname(item.bufnr) ~= filename
    end, vim.fn.getqflist() or {}),
    'r'
  )
end

local function clear()
  vim.fn.setqflist({}, 'r')
end

local function get_text()
  return table.concat(
    vim.tbl_map(
      function (item)
        local filetype = vim.bo[item.bufnr].filetype
        local filename = vim.fn.bufname(item.bufnr)

        local file_content = vim.api.nvim_buf_get_lines(item.bufnr, 0, -1, false)

        if #file_content == 0 then
          file_content = assert(vim.fn.readfile(filename), 'Failed to read file: ' .. filename)
        end

        return string.format(
          "File: `%s`\n```%s\n%s\n```\n\n",
          util.path.relative_norm(filename),
          filetype,
          table.concat(file_content, "\n")
        )
      end,
      vim.fn.getqflist() or {}
    )
  )
end

return {
  add = add,
  remove = remove,
  clear = clear,
  get_text = get_text
}
