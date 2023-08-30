local uv = vim.loop

-- TODO eventually switch to using vim.system(), neovim 0.10 feature
---@param cmd string
---@param args string[]
---@param on_stdout fun(text: string): nil
---@param on_error fun(text: string): nil
---@param opts? any additional options for uv.spawn
local function system(cmd, args, on_stdout, on_error, opts)
  local stdout = assert(uv.new_pipe(false), 'Failed to open stdout pipe')
  local stderr = assert(uv.new_pipe(false), 'Failed to open stderr pipe')

  local _error_output = ''

  local handle = assert(uv.spawn(
    cmd,
    vim.tbl_extend('force', {
      args = args,
      stdio = { nil, stdout, stderr }
    }, opts or {}),
    function(exit_code, signal)
      -- success
      if exit_code == 0 then return end

      -- sigint / cancelled
      if signal == 2 then return end

      on_error(_error_output)
    end
  ), 'curl exited unexpectedly')

  uv.read_start(stderr, function(err, text)
    assert(not err, err)
    if text then _error_output = _error_output .. text end
  end)

  uv.read_start(stdout, function(err, text)
    assert(not err, err)

    -- naked call to on_stdout that errors crashes nvim
    local success, handler_err_trace = xpcall(
      on_stdout,
      function()
        return debug.traceback('Error in system on_stdout handler', 2)
      end,
      text
    )

    if not success then
      error(handler_err_trace, 2)
    end
  end)

  return function() handle:kill("sigint") end
end

return system
