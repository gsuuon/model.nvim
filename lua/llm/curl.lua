local util = require("llm.util")
local uv = vim.loop

local M = {}

local function build_args(opts)
  return vim.tbl_flatten({
    {'-N', '-X', opts.method },
    util.table.map_to_array(opts.headers, function(k, v)
      return {'-H', k .. ': ' .. v}
    end),
    { '--data-raw', vim.json.encode(opts.body) },
    opts.url
  })
end

---@param opts { url : string, method : string, body : any, headers : {[string]: string} }
---@param on_stdout fun(text: string): nil
---@param on_error fun(text: string): nil
function M.stream(opts, on_stdout, on_error)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  if stdout == nil then return error("Failed to open stdout pipe") end
  if stderr == nil then return error("Failed to open stderr pipe") end

  local args = build_args(opts)

  local err_out = ""

  local handle, _ = uv.spawn('curl',
    {
      args = args,
      stdio = { nil, stdout, stderr }
    },
    function(exit_code)
      if exit_code ~= 0 then
        on_error(err_out)
      end
    end
  )

  uv.read_start(stderr, function(err, text)
    assert(not err, err)
    if text then err_out = err_out .. text end
  end)

  uv.read_start(stdout, function(err, text)
    assert(not err, err)
    if text then on_stdout(text) end
  end)

  return handle
end

return M
