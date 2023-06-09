if vim.g.did_setup_llm then
  return
end

require('llm').setup()

vim.g.did_setup_llm = true
