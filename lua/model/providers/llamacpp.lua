local curl = require('model.util.curl')
local util = require('model.util')
local async = require('model.util.async')
local system = require('model.util.system')
local provider_util = require('model.providers.util')
local llama2 = require('model.format.llama2')
local juice = require('model.util.juice')

local M = {}

local stop_server_augroup = vim.api.nvim_create_augroup('ModelNvimLlamaCppServerStop', {})

---@param model string
---@param args string[]
local function resolve_system_opts(model, args)
  assert(M.options, 'Missing llamacpp provider options. Call require("model.providers.llamacpp").setup({})')
  assert(M.options.binary, 'Llamacpp options missing server binary path')
  assert(M.options.models, 'Llamacpp options missing models path')

  local path = vim.fs.normalize(M.options.binary)
  local cmd = vim.fn.exepath(path)
  assert(cmd ~= '', 'Executable not found at ' .. path)

  local model_path = vim.fs.normalize(vim.fs.joinpath(M.options.models, model))

  return {
    cmd = cmd,
    args = util.list.append({ '-m', model_path }, args)
  }
end

local function start_server(model, args, on_started)
  local sys_opts = resolve_system_opts(model, args or {})

  local stop = system(
    sys_opts.cmd,
    sys_opts.args,
    {},
    function(out)
      if out and out:find('HTTP server listening') then
        util.show('llama.cpp server started')
        on_started()
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
    opts = util.list.append({model}, args),
    stop = stop
  }
end

local function start_opts_same(model, args)
  return util.list.equals(
    M.last_server.opts,
    util.list.append({model}, args)
  )
end

---Starts the server with model and args if needed. Stops last server and starts a new one if model or args have changed.
---@param model string
---@param args? string[]
---@param on_finish function
function M.start_server(model, args, on_finish)
  if M.last_server == nil then
    start_server(model, args, on_finish)
  else -- previously started server
    if start_opts_same(model, args) then
      vim.schedule(on_finish)
    else
      util.show('llama.cpp server restarting')
      M.last_server.stop()
      start_server(model, args, on_finish)
    end
  end
end

---@class LlamaCppOptions
---@field model? string Model to use with server autostart
---@field args? string[] Extra server args
---@field url? string Override default url

---@param handlers StreamHandlers
---@param params? any other params see : https://github.com/ggerganov/llama.cpp/blob/master/examples/server/README.md
---@param options? LlamaCppOptions
function M.request_completion(handlers, params, options)
  ---@type LlamaCppOptions
  local opts = vim.tbl_extend('force', {
    url = 'http://localhost:8080'
  }, options or {})

  local cancel = function() end

  async(function(wait, resolve)
    local stop_marquee = function() end

    if opts.model then
      stop_marquee = juice.handler_marquee_or_notify(
        'llama.cpp server starting',
        handlers.segment
      )
      wait(M.start_server(opts.model, opts.args, resolve))
      stop_marquee()
    end

    cancel = curl.stream(
      {
        url = opts.url .. '/completion',
        headers = {
          ['Content-Type'] = 'application/json'
        },
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

---@class LlamaCppSetupOptions
---@field binary string Server binary path
---@field models string Models directory

---@param options LlamaCppSetupOptions
function M.setup(options)
  M.options = options
end

return M
