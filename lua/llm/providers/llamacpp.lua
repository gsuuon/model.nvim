local curl = require('llm.util.curl')
local util = require('llm.util')
local async = require('llm.util.async')
local system = require('llm.util.system')
local provider_util = require('llm.providers.util')
local llama2 = require('llm.format.llama2')

local M = {}

local stop_server_augroup = vim.api.nvim_create_augroup('LlmNvimLlamaCppServerStop', {})

---@param start_command string[]
function M.start_server(start_command, cb)

  local function start_server()
    util.show('llama.cpp server starting')

    local command = start_command[1]
    local args = util.table.slice(command, 1)

    local stop = system(
      command, args,
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

    M.last_server = {
      command = start_command,
      stop = stop
    }
  end

  if M.last_server == nil then
    start_server()
  else -- previously started server
    if util.list.equals(M.last_server.command, start_command) then
      -- server already started with the same options
      vim.schedule(cb)
    else
      util.show('llama.cpp server restarting')
      M.last_server.stop()
      start_server()
    end
  end

end

---@alias LlamaCppOptions { server?: { command?: string[], url?: string } }

---@param handlers StreamHandlers
---@param params? any other params see : https://github.com/ggerganov/llama.cpp/blob/master/examples/server/README.md
---@param options? LlamaCppOptions set server.command to auto-start the llama.cpp server. Use complete paths.
---Example:
---```lua
---{
---  server = {
---    command = {
---      '/path/to/server',
---      '-m', '/path/to/model',
---      '-ngl', '20'
---    },
---    url = 'http://localhost:8080'
---  }
---}
---```
function M.request_completion(handlers, params, options)
  ---@type LlamaCppOptions
  local opts = vim.tbl_extend('force', {
    server = {
      url = 'http://localhost:8080'
    },
  }, options or {})

  local cancel = function() end

  async(function(wait, resolve)
    if opts.server.command then
      wait(M.start_server(opts.server, resolve))
    end

    cancel = curl.stream(
      {
        url = opts.server.url .. '/completion',
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
