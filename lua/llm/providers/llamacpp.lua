local curl = require('llm.util.curl')
local util = require('llm.util')
local async = require('llm.util.async')
local system = require('llm.util.system')
local provider_util = require('llm.providers.util')

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

---@param handlers StreamHandlers
---@param params? any other params see : https://github.com/ggerganov/llama.cpp/blob/master/examples/server/README.md
---@param options? { server_start?: { command: string, args: string[] }, server_port?: number } set server_start to auto-start llama.cpp server with a command and args. Paths should be absolute paths, example: { command = '/path/to/server', args = '-m /path/to/model -ngl 20'
function M.request_completion(handlers, params, options)

  ---@type { server_start?: { command: string, args: string[] }, server_port?: number }
  local options_ = vim.tbl_extend('force', { server_port = 8080 }, options or {})

  local cancel = function() end

  local function start_server(started_cb)
    util.show('llama.cpp server starting')

    local stop = system(
      options_.server_start.command,
      options_.server_start.args,
      {},
      function(out)
        if out and out:find('HTTP server listening') then
          util.show('llama.cpp server started')
          started_cb()
        end
      end,
      function(err)
        util.eshow(err)
      end
    )

    cancel = stop

    vim.api.nvim_create_autocmd('VimLeave', {
      group = stop_server_augroup,
      callback = stop
    })

    M.last_server_start = vim.tbl_extend(
      'force',
      options_.server_start,
      { stop = stop }
    )
  end

  async(function(wait, resolve)

    -- if we have a server start command, start the server and send request when it's up
    if options_.server_start then
      if M.last_server_start == nil then
        wait(start_server(resolve))
      else -- previously started server
        if start_opts_changed(M.last_server_start, options_.server_start) then
          M.last_server_start.stop()
          wait(start_server(resolve))
        end
      end
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

-- LLaMa 2

-- This stuff is adapted from https://github.com/facebookresearch/llama/blob/main/llama/generation.py
local SYSTEM_BEGIN = '<<SYS>>\n'
local SYSTEM_END = '\n<</SYS>>\n\n'
local INST_BEGIN = '<s>[INST]'
local INST_END = '[/INST]'

local function wrap_instr(text)
  return table.concat({
    INST_BEGIN,
    text,
    INST_END,
  }, '\n')
end

local function wrap_sys(text)
  return SYSTEM_BEGIN .. text .. SYSTEM_END
end

local default_system_prompt =
  [[You are a helpful, respectful and honest assistant. Always answer as helpfully as possible, while being safe. Your answers should not include any harmful, unethical, racist, sexist, toxic, dangerous, or illegal content. Please ensure that your responses are socially unbiased and positive in nature. If a question does not make any sense, or is not factually coherent, explain why instead of answering something not correct. If you don't know the answer to a question, please don't share false information.]]

---@param prompt { system?: string, messages: string[] } -- messages are alternating user/assistant strings
M.llama_2_chat = function(prompt)
  local texts = {}

  for i, message in ipairs(prompt.messages) do
    if i % 2 == 0 then
      table.insert(texts, wrap_instr(message))
    else
      table.insert(texts, message)
    end
  end

  return wrap_sys(prompt.system or default_system_prompt) .. table.concat(texts, '\n') .. '\n'
end

---@param prompt { system?: string, message: string }
M.llama_2_system_prompt = function(prompt) -- correct but does not give as good results as llama_2_user_prompt
  return wrap_instr(wrap_sys(prompt.system or default_system_prompt) .. prompt.message)
end

---@param prompt { user: string, message: string } -- for coding problems
M.llama_2_user_prompt = function(prompt) -- somehow gives better results compared to sys prompt way...
  return wrap_instr(prompt.user .. "\n'''\n" .. prompt.message .. "\n'''\n") -- wrap messages in '''
end

---@param prompt { system?:string, user: string, message?: string }
M.llama_2_general_prompt = function(prompt) -- somehow gives better results compared to sys prompt way...
  local message = ''
  if prompt.message ~= nil then
    message = "\n'''\n" .. prompt.message .. "\n'''\n"
  end
  -- best way to format is iffy. better: wrap_system() .. wrap_instr(), but should be: wrap_instr(wrap_system(sys_msg) .. message) by docs
  return wrap_instr(wrap_sys(prompt.system or default_system_prompt) .. prompt.user .. message)
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
            prompt = M.llama_2_user_prompt({user = user_input or '', message = input})
          })
        end)
    end
  end
}

return M
