return {
  description = 'List all Neovim buffers (similar to :ls)',
  parameters = {
    type = 'object',
    properties = vim.empty_dict(),
    required = {},
  },
  invoke = function()
    local buffers = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local buf_name = vim.api.nvim_buf_get_name(bufnr)
      local is_loaded = vim.api.nvim_buf_is_loaded(bufnr)
      table.insert(buffers, {
        number = bufnr,
        name = buf_name,
        loaded = is_loaded,
      })
    end
    return buffers
  end,
}
