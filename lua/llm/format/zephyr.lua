local llamacpp = require('llm.providers.llamacpp')

local util = require('llm.util')
local curl = require('llm.util.curl')
local async = require('llm.util.async')

local M = {}

---Formats LlmChatContents to strings, which can be tokenized and EOS added to each message. This lets LlamaCpp naturally emit an EOS in assistant response so we don't need
---to use a stop string.
---reference: https://huggingface.co/HuggingFaceH4/zephyr-7b-beta
---@param contents LlmChatContents
---@param include_continue boolean Include the continue partial `\n<|assistant|>\n` as the last string. Avoid adding EOS to the last string for chat prompts.
---@return string[]
function M.contents_to_strings(contents, include_continue)
  local system = contents.system or 'You are a helpful assistant.'

  local result = {'<|system|>\n' .. system}

  for _,msg in ipairs(contents.messages) do
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

---Tokenizes each message and system separately then inserts an EOS (2) token between each item.
---@param contents LlmChatContents
---@param url_base string
---@param cb fun(tokens: number[]): any
local function tokenize_messages(contents, url_base, cb)
  local BOS = 1
  local EOS = 2

  local formatted_messages = M.contents_to_strings(contents, true)

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

---Tokenizes each message individually and adds a 2 (EOS) token between messages.
function M.chatprompt_run(contents)
  return function(config)
    async(function(wait, resolve)
      if contents.config.options.server_start then
        wait(llamacpp.start_server(contents.config.options.server_start, resolve))
      end

      tokenize_messages(contents, nil, function(tokens)
        config({
          options = contents.config.options,
          params = {
            prompt = tokens
          }
        })
      end)
    end)
  end
end


return M
