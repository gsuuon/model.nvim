if vim.g.did_setup_model then
  return
end

vim.filetype.add({
  extension = {
    mchat = 'mchat',
  }
})

require('llm').setup({
  prompts = require('llm.prompts.starters'),
  chats = require('llm.prompts.chats')
})
