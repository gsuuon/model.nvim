local system = require('llm.util.system')

local curl = require "llm.curl"
local util = require "llm.util"
local provider_util = require "llm.providers.util"

local M = {}

---@param handlers StreamHandlers
---@param params? any Additional params for request
---@param options? { model?: string }
function M.request_completion(handlers, params, options)
  local model = (options or {}).model or "bigscience/bloom"
  -- vim.print(params)

  -- TODO handle non-streaming calls
  return curl.stream({
    -- url = 'https://api-inference.huggingface.co/models/', --.. model,
    url = "http://127.0.0.1:8080/completion",
    method = "POST",
    body = vim.tbl_extend("force", { stream = true }, params),
    headers = {
      -- Authorization = 'Bearer ' .. util.env_memo('HUGGINGFACE_API_KEY'),
      ["Content-Type"] = "application/json",
      -- ['data'] = '{"prompt": "Building a website can be done in 10 simple steps:","n_predict": 128}',
    },
  }, function(raw)

    provider_util.iter_sse_items(raw, function(item)
      local data = util.json.decode(item)

      if data == nil then
        handlers.on_error(item, "json parse error")
        return
      end

      if data.generation_settings ~= nil then -- last message
        handlers.on_finish('', "stop")
        return
      end

      handlers.on_partial(data.content)

    end)



  end, function(error)
    handlers.on_error(error)
  end)
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


M.default_prompt = {
  provider = M,
  options = {
    -- model = 'bigscience/bloom'
  },
  params = {
    return_full_text = false,
  },
  builder = function(input)
    return {
      prompt = M.llama_2_format {
        messages = {
          input,
        },
      },
    }
  end,
}

return M
