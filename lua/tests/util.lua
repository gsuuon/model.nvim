local M = {}

function M.type_keys(keys, flags)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(keys, true, false, true),
    flags or 'x',
    false
  )
end

return M
