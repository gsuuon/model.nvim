local model = require('model')

local M = vim.tbl_extend('force', model, {})

M.setup = function(...)
  vim.notify([[gsuuon/llm.nvim has been renamed to gsuuon/model.nvim, please use `require('model')` instead of `require('llm')`]], vim.log.levels.WARN)

  model.setup(...)
end

return model
