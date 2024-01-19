-- TODO clean this up
local M = {}

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
M.chat = function(prompt)
  local texts = {}

  for i, message in ipairs(prompt.messages) do
    if i % 2 == 0 then
      table.insert(texts, wrap_instr(message))
    else
      table.insert(texts, message)
    end
  end

  return wrap_sys(prompt.system or default_system_prompt)
    .. table.concat(texts, '\n')
    .. '\n'
end

---@param prompt { system?: string, message: string }
M.system_prompt = function(prompt) -- correct but does not give as good results as user_prompt
  return wrap_instr(
    wrap_sys(prompt.system or default_system_prompt) .. prompt.message
  )
end

---@param prompt { user: string, message: string } -- for coding problems
M.user_prompt = function(prompt) -- somehow gives better results compared to sys prompt way...
  return wrap_instr(prompt.user .. "\n'''\n" .. prompt.message .. "\n'''\n") -- wrap messages in '''
end

---@param prompt { system?:string, user: string, message?: string }
M.general_prompt = function(prompt) -- somehow gives better results compared to sys prompt way...
  local message = ''
  if prompt.message ~= nil then
    message = "\n'''\n" .. prompt.message .. "\n'''\n"
  end
  -- best way to format is iffy. better: wrap_system() .. wrap_instr(), but should be: wrap_instr(wrap_system(sys_msg) .. message) by docs
  return wrap_instr(
    wrap_sys(prompt.system or default_system_prompt) .. prompt.user .. message
  )
end

return M
