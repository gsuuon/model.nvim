local system = require "llm.util.system"

local curl = require "llm.curl"
local util = require "llm.util"
local provider_util = require "llm.providers.util"
-- local extract = require('llm.prompts.extract')

local M = {}

---@param handlers StreamHandlers
---@param params? any Additional params for request
---@param options? { model?: string }
function M.request_completion(handlers, params, options)

  -- TODO handle non-streaming calls
  return curl.stream({
    url = "http://127.0.0.1:8080/completion",
    method = "POST",
    body = vim.tbl_extend("force", { stream = true }, params),
  }, function(raw)
    provider_util.iter_sse_items(raw, function(item)
      local data = util.json.decode(item)

      if data == nil then
        handlers.on_error(item, "json parse error")
        return
      end

      if data.generation_settings ~= nil then -- last message
        handlers.on_finish()
        return
      end

      handlers.on_partial(data.content)
    end)
  end, function(error)
    handlers.on_error(error)
  end)
end

-- LLaMa 2


-- example code prompt llama2:
-- [===[
-- <s>[INST] Write code to solve the following coding problem that obeys the constraints and passes the example test cases. Please wrap your code answer using ```.
-- ]===]
-- .. user_input ..
-- [===[
-- [/INST]
-- ]===]

-- example noncoder prompt llama2:
-- <s>[INST] <<SYS>>
-- You are a helpful, respectful and honest assistant. Always answer as helpfully as possible, while being safe.  Your answers should not include any harmful, unethical, racist, sexist, toxic, dangerous, or illegal content. Please ensure that your responses are socially unbiased and positive in nature.
--
-- If a question does not make any sense, or is not factually coherent, explain why instead of answering something not correct. If you don't know the answer to a question, please don't share false information.
-- <</SYS>>
--
-- There's a llama in my garden 😱 What should I do? [/INST]



-- This stuff is adapted from https://github.com/facebookresearch/llama/blob/main/llama/generation.py
local SYSTEM_BEGIN = "<<SYS>>\n"
local SYSTEM_END = "\n<</SYS>>\n\n"
local INST_BEGIN = "<s>[INST]"
local INST_END = "[/INST]"

local function wrap_instr(text)
  return table.concat({
    INST_BEGIN,
    text,
    INST_END,
  }, "\n")
end

local function wrap_sys(text)
  return SYSTEM_BEGIN .. text .. SYSTEM_END
end

local default_system_prompt =
  [[You are a helpful, respectful and honest assistant. Always answer as helpfully as possible, while being safe. Your answers should not include any harmful, unethical, racist, sexist, toxic, dangerous, or illegal content. Please ensure that your responses are socially unbiased and positive in nature. If a question does not make any sense, or is not factually coherent, explain why instead of answering something not correct. If you don't know the answer to a question, please don't share false information.]]

local coding_system_prompt =
  [[ Write code to solve the following coding problem that obeys the constraints and passes the example test cases. Please wrap your code answer using ```. ]]

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

  return wrap_sys(prompt.system or default_system_prompt) .. table.concat(texts, "\n") .. "\n"
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
  local message = ""
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
    -- other params see : https://github.com/ggerganov/llama.cpp/blob/master/examples/server/README.md
  },
  -- builder = function(input)
  --   return {
  --     prompt = M.llama_2_chat { messages = { input, }, },
  --   }
  -- end,
  builder = function(input)
    return function(build)
      vim.ui.input(
        { prompt = 'Instruction: ' },
        function(user_input)
          if user_input == nil then return end

          local final_prompt = ''
          if #user_input > 0 then
            final_prompt = M.llama_2_user_prompt({user = user_input, message = input})
          else
            return
          end

          -- vim.print(final_prompt)
          build({
            prompt = final_prompt
          })
        end)
    end
  end,
  -- transform = extract.markdown_code, -- only use code block from server response

}

return M
