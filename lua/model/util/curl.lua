local util = require('model.util')
local system = require('model.util.system')

local M = {}

local function build_args(opts, stream, with_headers)
  local args = {
    '-sS', -- silent (no progress) but show errors
  }

  if with_headers then
    table.insert(args, '-i')
  end

  if opts.args ~= nil and vim.tbl_islist(opts.args) then
    for _, arg in ipairs(opts.args) do
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
    table.insert(args, '@-') -- read from stdin
  end

  table.insert(args, opts.url)

  return args
end

-- TODO -w "%{stderr}%{response_code}" to get status code from stderr
---@param opts { url : string, method : string, body : any, headers : {[string]: string} }
---@param stream boolean
---@param on_stdout fun(text: string): nil
---@param on_error fun(text: string): nil
---@param on_exit? fun(): nil
---@param on_headers? fun(headers: string): nil
local function run_curl(opts, stream, on_stdout, on_error, on_exit, on_headers)
  local args = build_args(opts, stream, on_headers ~= nil)
  local input = vim.json.encode(opts.body)

  if M._is_debugging then
    util.show(args, 'curl args')
    util.show(vim.json.decode(input), 'curl body')
  end

  local on_curl_out = on_stdout
  if on_headers then
    local buffered = ''
    local got_headers = false

    on_curl_out = function(out)
      if got_headers then
        if out ~= nil then
          out = out:gsub('\r', '')
        end
        on_stdout(out)
      else
        buffered = buffered .. out:gsub('\r', '')

        local headers, rest = buffered:match('^(HTTP/.-)\n\n(.*)')
        if headers then
          got_headers = true
          on_headers(headers)
          on_stdout(rest)
        end
      end
    end
  end

  return system('curl', args, {}, on_curl_out, on_error, on_exit, input)
end

---@param opts { url : string, method : string, body : any, headers : {[string]: string} }
---@param on_complete fun(text: string): nil
---@param on_error fun(text: string): nil
---@return fun(): nil cancel_stream Cancels the stream process
function M.request(opts, on_complete, on_error)
  local output = ''

  local function on_stdout(out)
    if out ~= nil then
      output = output .. out
    end
  end

  local function on_exit()
    on_complete(output)
  end

  return run_curl(opts, false, on_stdout, on_error, on_exit)
end

---@param opts { url : string, method : string, body : any, headers : {[string]: string} }
---@param on_stdout fun(text: string): nil
---@param on_error fun(text: string): nil
---@param on_exit? fun(): nil
---@param on_headers? fun(headers: string): nil
function M.stream(opts, on_stdout, on_error, on_exit, on_headers)
  local function on_out(out)
    if out ~= nil then
      on_stdout(out)
    end
  end

  return run_curl(opts, true, on_out, on_error, on_exit, on_headers)
end

return M
