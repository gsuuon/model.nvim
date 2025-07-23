local function notify(method, data)
  -- vim.rpcnotify(0, 'model_nvim', method, data)
  -- rpcnotify(0, 'model_nvim') will cause pynvim to throw error messages
  -- need to only notify deno-ui's if they're attached
end

return {
  notify = notify,
}
