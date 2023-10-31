local util = require('llm.util')
local system = require('llm.util.system')

local M = {}

local function build_args(opts, stream)
  local args = {
    '-sS', -- silent (no progress) but show errors
  }

  if opts.args ~= nil and vim.tbl_islist(opts.args) then
    for _,arg in ipairs(opts.args) do
      table.insert(args, arg)
    end
  end

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

-- TODO -w "%{stderr}%{response_code}" to get status code from stderr
---@param opts { url : string, method : string, body : any, headers : {[string]: string} }
---@param stream boolean
---@param on_stdout fun(text: string): nil
---@param on_error fun(text: string): nil
local function run_curl(opts, stream, on_stdout, on_error)
  local args = build_args(opts, stream)

  if M._is_debugging then
    util.show(args, 'curl args')
  end

  return system('curl', args, {}, on_stdout, on_error)
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
