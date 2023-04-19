local util = require('llm.util')
local uv = vim.loop

local M = {}

local function build_args(opts)
  return vim.tbl_flatten({
    '-N',
    '-X', opts.method,
    util.table.map_to_array(opts.headers, function(k, v)
      return {'-H', k .. ': ' .. v}
    end),
    '--data-raw', vim.json.encode(opts.body),
    opts.url
  })
end

---@param opts { url : string, method : string, body : any, headers : {[string]: string} }
---@param on_stdout fun(text: string): nil
---@param on_error fun(text: string): nil
---@return fun(): nil cancel_stream Cancels the stream process
function M.stream(opts, on_stdout, on_error)
  if M._is_debugging then
    util.show(opts.body, 'Request body')
  end

  local stdout = assert(uv.new_pipe(false), 'Failed to open stdout pipe')
  local stderr = assert(uv.new_pipe(false), 'Failed to open stderr pipe')

  local _error_output = ''

  local handle = assert(uv.spawn('curl',
    {
      args = build_args(opts),
      stdio = { nil, stdout, stderr }
    },
    function(exit_code, signal)
      -- success
      if exit_code == 0 then return end

      -- sigint / cancelled
      if exit_code == 1 and signal == 2 then return end

      on_error(
        vim.inspect({
          exit_code = exit_code,
          signal = signal,
        }) .. '\n' .. _error_output
      )
    end
  ), 'Failed to open stderr pipe')

  uv.read_start(stderr, function(err, text)
    assert(not err, err)
    if text then _error_output = _error_output .. text end
  end)

  uv.read_start(stdout, function(err, text)
    assert(not err, err)
    if text then on_stdout(text) end
  end)

  return function() handle:kill("sigint") end
end

return M
