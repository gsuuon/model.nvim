local M = {}

local function tbl_as_args(tbl)
  local args = {}
  for k,v in pairs(tbl) do
    table.insert(args, '--'..k)
    table.insert(args, v)
  end

  return args
end

---@param handlers StreamHandlers
---@param params any Parameters for call
---@param options { path: string, main_dir: string, stop?: string } Path to llamacpp root (contains ./build and ./models)
function M.request_completion(handlers, params, options)
  assert(vim.system, 'Missing vim.system - upgrade to neovim 0.10+')

  local exec = vim.fs.normalize(vim.fs.joinpath(
    assert(options.path, 'Missing path in llamacpp prompt options. If using the starter, make sure to set LLAMACPP_DIR.'),
    options.main_dir or 'build/bin/Release/',
    'main'
  ))

  local args = tbl_as_args(params)

  local stderr = {}
  local stdout = {}

  local did_ignore_initial_prompt = false

  local proc

  proc = vim.system(
    vim.tbl_flatten({exec, args}),
    {
      cwd = vim.fs.normalize(options.path),
      env = {}, -- getting dll linking errors on windows if we dont passthrough env (exit 3221225781)
      stdout = function(err, data)
        assert(not err, err)

        if data then
          local data_ = data:gsub('\r\n', '\n')

          -- I imagine there's a cli option to not output the initial prompt, but I haven't been able to find it
          if not did_ignore_initial_prompt
            -- llama.cpp prepends an empty space before the prompt
            -- https://github.com/ggerganov/llama.cpp/blob/294f424554c1599784ac9962462fc39ace92d8a5/examples/main/main.cpp#L200
            and data_ == ' ' .. params.prompt:gsub('\r\n', '\n')
          then
            did_ignore_initial_prompt = true
          else
            if data_ == options.stop then
              proc:kill(2)
            else
              handlers.on_partial(data_)
              table.insert(stdout, data_)
            end
          end
        end
      end,
      stderr = function(err, data)
        assert(not err, err)

        if data then
          table.insert(stderr, data)
        end
      end,
    },
    function(completed)
      if completed.code ~= 0 then
        handlers.on_error(table.concat(stderr, '\n'))
      else
        handlers.on_finish(table.concat(stdout, ''))
      end
    end
  )

  return function()
    proc:kill(2)
  end
end

-- LLaMa 2
-- This stuff is adapted from https://github.com/facebookresearch/llama/blob/main/llama/generation.py
local SYSTEM_BEGIN = '<<SYS>>\n'
local SYSTEM_END = '\n<</SYS>>\n\n'
local INST_BEGIN = '[INST]'
local INST_END = '[/INST]'

local function as_user(text)
  return table.concat({
    INST_BEGIN,
    text,
    INST_END,
  }, '\n')
end

local function as_system_prompt(text)
  return SYSTEM_BEGIN .. text .. SYSTEM_END
end

local default_system_prompt =
  [[You are a helpful, respectful and honest assistant. Always answer as helpfully as possible, while being safe. Your answers should not include any harmful, unethical, racist, sexist, toxic, dangerous, or illegal content. Please ensure that your responses are socially unbiased and positive in nature. If a question does not make any sense, or is not factually coherent, explain why instead of answering something not correct. If you don't know the answer to a question, please don't share false information.]]

---@param prompt { system?: string, messages: string[] } -- messages are alternating user/assistant strings
M.llama_2_format = function(prompt)
  local texts = {}

  for i,message in ipairs(prompt.messages) do
    if i % 2 == 0 then
      table.insert(texts, message)
    else
      table.insert(texts, as_user(message))
    end
  end

  return
    as_system_prompt(prompt.system or default_system_prompt)
    .. table.concat(texts, '\n')
    .. '\n'
end

return M
