vim.notify(
  [[require('llm.prompts') is deprecated, use require('llm.util.prompts')]],
  vim.log.levels.WARN
)

return require('llm.util.prompts')
