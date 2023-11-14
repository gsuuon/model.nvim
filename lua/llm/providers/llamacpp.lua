local curl = require('llm.util.curl')
local util = require('llm.util')
local async = require('llm.util.async')
local system = require('llm.util.system')
local provider_util = require('llm.providers.util')
local llama2 = require('llm.format.llama2')

local M = {}

local stop_server_augroup = vim.api.nvim_create_augroup('LlmNvimLlamaCppServerStop', {})

local function start_opts_changed(a, b)
  if a == b then
    return false
  end

  if a.command ~= b.command then
    return true
  end

  if table.concat(a.args, ' ') ~= table.concat(b.args, ' ') then
    return true
  end
end

function M.start_server(server_start_options, cb)

  local function start_server()
    util.show('llama.cpp server starting')

    local stop = system(
      server_start_options.command,
      server_start_options.args,
      {},
      function(out)
        if out and out:find('HTTP server listening') then
          util.show('llama.cpp server started')
          cb()
        end
      end,
      function(err)
        util.eshow(err)
      end
    )

    vim.api.nvim_create_autocmd('VimLeave', {
      group = stop_server_augroup,
      callback = stop
    })

    M.last_server_start = vim.tbl_extend(
      'force',
      server_start_options,
      { stop = stop }
    )
  end

  if M.last_server_start == nil then
    start_server()
  else -- previously started server
    if start_opts_changed(M.last_server_start, server_start_options) then
      util.show('llama.cpp server restarting')
      M.last_server_start.stop()
      start_server()
    else
      -- server already started with the same options
      vim.schedule(cb)
    end
  end

end

---@param handlers StreamHandlers
---@param params? any other params see : https://github.com/ggerganov/llama.cpp/blob/master/examples/server/README.md
---@param options? { server_start?: { command: string, args: string[] }, server_port?: number } set server_start to auto-start llama.cpp server with a command and args. Paths should be absolute paths, example: { command = '/path/to/server', args = '-m /path/to/model -ngl 20'
function M.request_completion(handlers, params, options)
  ---@type { server_start?: { command: string, args: string[] }, server_port?: number }
  local options_ = vim.tbl_extend('force', { server_port = 8080 }, options or {})

  local cancel = function() end

  async(function(wait, resolve)
    if options_.server_start then
      wait(M.start_server(options_.server_start, resolve))
    end

    cancel = curl.stream(
      {
        url = 'http://127.0.0.1:' .. options_.server_port .. '/completion',
        method = 'POST',
        body = vim.tbl_extend('force', { stream = true }, params),
      },
      provider_util.iter_sse_data(function(item)
        local data = util.json.decode(item)

        if data == nil then
          handlers.on_error(item, 'json parse error')
        elseif data.stop then
          handlers.on_finish()
        else
          handlers.on_partial(data.content)
        end
      end),
      function(error)
        handlers.on_error(error)
      end)
  end)

  return function() cancel() end
end

M.default_prompt = {
  provider = M,
  params = {
    temperature = 0.8,    -- Adjust the randomness of the generated text (default: 0.8).
    repeat_penalty = 1.1, -- Control the repetition of token sequences in the generated text (default: 1.1)
    seed = -1,            -- Set the random number generator (RNG) seed (default: -1, -1 = random seed)
  },
  builder = function(input)
    return function(build)
      vim.ui.input(
        { prompt = 'Instruction: ' },
        function(user_input)
          build({
            prompt = llama2.user_prompt({user = user_input or '', message = input})
          })
        end)
    end
  end
}

return M
