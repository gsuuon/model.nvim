if vim.g.did_setup_llm then
  return
end

vim.filetype.add({
  extension = {
    llmchat = 'llmchat',
  }
})

require('llm').setup({
  prompts = require('llm.prompts.starters')
})
