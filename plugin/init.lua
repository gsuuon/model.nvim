if vim.g.did_setup_llm then
  return
end

require('llm').setup({
  prompts = require('llm.prompts.starters')
})
