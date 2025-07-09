if vim.g.did_setup_model_filetype then
  return
end

vim.filetype.add({
  extension = {
    mchat = 'mchat',
  },
})

vim.g.did_setup_model_filetype = true
