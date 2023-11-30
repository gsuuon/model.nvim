local llamacpp = require('llm.providers.llamacpp')

local util = require('llm.util')
local curl = require('llm.util.curl')
local async = require('llm.util.async')

local M = {}

---Format LlmChatContents to a string list so they can be individually tokenized.
---reference: https://huggingface.co/HuggingFaceH4/zephyr-7b-beta
---@param messages LlmChatMessage[]
---@param system string
---@param include_continue? boolean Include the continue partial `\n<|assistant|>\n` as the last string. Avoid adding EOS to the last string for chat prompts.
---@return string[]
function M.contents_to_strings(messages, system, include_continue)
  local result = {
    '<|system|>\n' .. system
  }

  for _,msg in ipairs(messages) do
    table.insert(result, '\n<|' ..  msg.role .. '|>\n' .. msg.content)
  end

  if include_continue then
    table.insert(result, '\n<|assistant|>\n')
  end

  return result
end

local function tokenize(text, url_base, cb)
  curl.request(
    {
      url = url_base .. '/tokenize',
      body = { content = text, }
    },
    function(x)
      local tokens = vim.json.decode(x).tokens

      cb(tokens)
    end,
    util.eshow
  )
end

---Tokenizes each message with LlamaCpp server separately then inserts an EOS (2) token between each item.
---@param messages LlmChatMessage[]
---@param system string
---@param url_base string
---@param cb fun(tokens: number[]): any
local function tokenize_messages(messages, system, url_base, cb)
  local BOS = 1
  local EOS = 2

  local formatted_messages = M.contents_to_strings(messages, system, true)

  async(function(wait, resolve)
    local tokens_list = {
      {BOS}
    }

    for i,msg in ipairs(formatted_messages) do
      local tokens = wait(tokenize(msg, url_base, resolve))

      if i ~= #formatted_messages then
        -- Don't add EOS to the last string which we're continuing
        table.insert(tokens, EOS)
      end

      table.insert(tokens_list, tokens)
    end

    return vim.tbl_flatten(tokens_list)
  end, cb)
end

---Use as ChatPrompt.run in a zephyr ChatPrompt.
---Tokenizes each message individually and adds a 2 (EOS) token between messages.
---@param messages LlmChatMessage[]
---@param config table
function M.chatprompt_run(messages, config)
  local options = config.options or {}

  return function(set_params)
    async(function(wait, resolve)
      if options.model then
        wait(llamacpp.start_server(
          options.model,
          options.args,
          resolve
        ))
      end

      local tokens = wait(
        tokenize_messages(
          messages,
          config.system or 'You are a helpful assistant',
          options.url or 'http://localhost:8080',
          resolve
        )
      )

      set_params({
        prompt = tokens
      })
    end)
  end
end

return M
