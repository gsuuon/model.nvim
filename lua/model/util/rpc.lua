return {
  notify = function(method, data)
    vim.rpcnotify(0, 'model_nvim', method, data)
  end,
}
