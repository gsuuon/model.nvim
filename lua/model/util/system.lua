local uv = vim.loop

-- TODO eventually switch to using vim.system(), neovim 0.10 feature
---@param cmd string
---@param args string[]
---@param opts? object additional options for uv.spawn
---@param on_stdout? fun(text: string): nil
---@param on_error? fun(text: string): nil
---@param on_exit? fun(): nil
---@param stdin_text? string
---@return function interrupt sends SIGINT to process
local function system(cmd, args, opts, on_stdout, on_error, on_exit, stdin_text)
  local stdout = assert(uv.new_pipe(false), 'Failed to open stdout pipe')
  local stderr = assert(uv.new_pipe(false), 'Failed to open stderr pipe')
  local stdin = assert(uv.new_pipe(false), 'Failed to open stdin pipe')

  local _error_output = ''
  local _did_finish_read_stdin = false
  local _can_exit = false

  local handle = assert(
    uv.spawn(
      cmd,
      vim.tbl_extend('force', {
        args = args,
        stdio = { stdin, stdout, stderr },
      }, (opts or {})),
      function(exit_code, signal)
        -- success
        if exit_code == 0 then
          if on_exit ~= nil then
            vim.schedule(function()
              if _did_finish_read_stdin then
                on_exit()
              else
                _can_exit = true
              end
            end)
          end

          return
        end

        -- sigint / cancelled
        if signal == 2 then
          return
        end

        if on_error then
          vim.schedule(function()
            on_error(_error_output)
          end)
        end
      end
    ),
    'failed to spawn ' .. cmd
  )

  uv.read_start(stderr, function(err, text)
    assert(not err, err)
    if text then
      _error_output = _error_output .. text
    end
  end)

  if on_stdout then
    uv.read_start(stdout, function(err, text)
      assert(not err, err)

      if text == nil then -- nil means EOF
        if _can_exit and on_exit then
          on_exit()
        else
          _did_finish_read_stdin = true
        end
      else
        -- naked call to on_stdout that errors crashes nvim
        local success, handler_err_trace = xpcall(
          vim.schedule_wrap(on_stdout),
          function()
            return debug.traceback('Error in system on_stdout handler', 2)
          end,
          text
        )

        if not success then
          error(handler_err_trace, 2)
        end
      end
    end)
  end

  if stdin_text then
    stdin:write(stdin_text)
  end

  stdin:shutdown()

  return function()
    handle:kill('sigint')
  end
end

return system
