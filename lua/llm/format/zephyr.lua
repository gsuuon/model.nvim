local M = {}

---Formats LlmChatContents to a zephyr template
---reference: https://huggingface.co/HuggingFaceH4/zephyr-7b-beta
---@param contents LlmChatContents
function M.from_chat_contents(contents)
  local system = contents.system or 'You are a helpful assistant.'

  local result = '<|system|>\n' .. system .. '</s>'

  for _,msg in ipairs(contents.messages) do
    result = result .. '\n<|' ..  msg.role .. '|>\n' .. msg.content .. '</s>'
  end

  if vim.tbl_get(contents.messages, #contents.messages, 'role') ~= 'assistant' then
    result = result .. '\n<|assistant|>\n'
  end

  return result
end

local curl = require('llm.util.curl')
local async = require('llm.util.async')
local util = require('llm.util')

local function detokenize(tokens, cb)
  curl.request(
    {
      url = 'http://localhost:8080/detokenize',
      body = { tokens = tokens }
    },
    function(x)
      local res = vim.json.decode(x, {})

      cb({
        text = res.content,
        tokens = tokens
      })
    end,
    util.eshow
  )
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

---@param contents LlmChatContents
local function as_formatted_messages(contents)
  local formatted = {}

  if contents.system then
    table.insert(formatted, '<|system|>\n' .. contents.system)
  end

  for _,msg in ipairs(contents.messages) do
    table.insert(formatted, '<|' ..  msg.role .. '|>\n' .. msg.content)
  end

  return formatted
end

---Tokenizes each message and system separately then inserts an EOS (2) token between each item.
---@param contents LlmChatContents
---@param url_base? string
---@param cb fun(tokens: number[]): any
function M.tokenize(contents, url_base, cb)
  local BOS = 1
  local EOS = 2

  local url_ = url_base or 'http://localhost:8080'

  local formatted_messages = as_formatted_messages(contents)

  async(function(wait, resolve)
    local results = {BOS}

    for _,msg in ipairs(formatted_messages) do
      local tokens = wait(tokenize(msg, url_, resolve))
      for _,tok in ipairs(tokens) do
        table.insert(results, tok)
      end

      table.insert(results, EOS)
    end

    show({results = results})

    return results
  end, cb)
end

-- M.tokenize({
--   system = 'hi',
--   messages = {
--     {
--       role = 'user',
--       content = 'count to three'
--     }
--   }
-- }, nil, util.show)

return M
