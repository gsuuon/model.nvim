vim.notify(
  [[require('model.prompts') is deprecated, use require('model.util.prompts')]],
  vim.log.levels.WARN
)

return require('model.util.prompts')
