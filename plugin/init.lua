if vim.g.did_setup_model then
  return
end

vim.filetype.add({
  extension = {
    mchat = 'mchat',
  }
})

require('model').setup({
  prompts = require('model.prompts.starters'),
  chats = require('model.prompts.chats')
})
