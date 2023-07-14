local util = require('llm.util')
local uv = vim.loop

local M = {}

local function build_args(opts, stream)
  local args = {
    '-sS', -- silent (no progress) but show errors
  }

  if stream then
    table.insert(args, '-N') -- no buffer
  end

  if opts.method ~= nil then
    table.insert(args, '-X')
    table.insert(args, opts.method)
  end

  if opts.headers ~= nil then
    for k, v in pairs(opts.headers) do
      table.insert(args, '-H')
      table.insert(args, k .. ': ' .. v)
    end
  end

  if opts.body ~= nil then
    table.insert(args, '--data-binary')
    table.insert(args, vim.json.encode(opts.body))
  end

  table.insert(args, opts.url)

  return args
end


-- TODO eventually switch to using vim.system(), neovim 0.10 feature
-- TODO -w "%{stderr}%{response_code}" to get status code from stderr
---@param opts { url : string, method : string, body : any, headers : {[string]: string} }
---@param on_stdout fun(text: string): nil
---@param on_error fun(text: string): nil
local function run_curl(opts, stream, on_stdout, on_error)
  local stdout = assert(uv.new_pipe(false), 'Failed to open stdout pipe')
  local stderr = assert(uv.new_pipe(false), 'Failed to open stderr pipe')

  local _error_output = ''

  local args = build_args(opts, true, stream)

  if M._is_debugging then
    util.show(args, 'curl args')
  end

  local handle = assert(uv.spawn('curl',
    {
      args = args,
      stdio = { nil, stdout, stderr }
    },
    function(exit_code, signal)
      -- success
      if exit_code == 0 then return end

      -- sigint / cancelled
      if exit_code == 1 and signal == 2 then return end

      on_error(_error_output)
    end
  ), 'curl exited unexpectedly')

  uv.read_start(stderr, function(err, text)
    assert(not err, err)
    if text then _error_output = _error_output .. text end
  end)

  uv.read_start(stdout, function(err, text)
    assert(not err, err)
    on_stdout(text)
  end)

  return function() handle:kill("sigint") end
end

---@param opts { url : string, method : string, body : any, headers : {[string]: string} }
---@param on_complete fun(text: string): nil
---@param on_error fun(text: string): nil
---@return fun(): nil cancel_stream Cancels the stream process
function M.request(opts, on_complete, on_error)
  local output = ''

  local function on_stdout(out)
    if out == nil then
      on_complete(output)
    else
      output = output .. out
    end
  end

  return run_curl(opts, false, on_stdout, on_error)
end

function M.stream(opts, on_stdout, on_error)
  local function on_out(out)
    if out ~= nil then
      on_stdout(out)
    end
  end

  return run_curl(opts, true, on_out, on_error)
end

return M
