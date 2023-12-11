local M = {}

---@deprecated Broken when string is quote wrapped. Prefer vim.eval.
function M.escape_quotes(str)
  return [[r"""]] .. str:gsub([["""]], [[\"\"\"]]) .. [["""]]
end

--- This only works if immediately used in a py3eval - otherwise the value will just be the last set
--- As in, can't call to_py on several variables before running py3eval
local function to_py(x)
  vim.g.__model_python_call_arg = x

  return 'vim.eval("g:__model_python_call_arg")'
end

function M.tiktoken_count(text)
  vim.cmd([[
    py import store
    py import json
  ]])

  if text == nil then
    text = table.concat(vim.api.nvim_buf_get_lines(0, 1, -1, false), '\n')
  end

  return vim.fn.py3eval('store.count_tokens(' .. to_py(text) .. ')')
end

return M

