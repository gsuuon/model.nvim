local M = {}

---Formats LlmChatContents to a zephyr template. Adds </s> between each string.
---</s> does not properly tokenize with llamacpp to EOS but can still be used as
---a stop.
---reference: https://huggingface.co/HuggingFaceH4/zephyr-7b-beta
---@param contents LlmChatContents
---@return string
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

---Formats LlmChatContents to a zephyr template
---reference: https://huggingface.co/HuggingFaceH4/zephyr-7b-beta
---@param contents LlmChatContents
---@return string[]
function M.from_chat_contents_to_strings(contents)
  local system = contents.system or 'You are a helpful assistant.'

  local result = {'<|system|>\n' .. system}

  for _,msg in ipairs(contents.messages) do
    table.insert(result, '\n<|' ..  msg.role .. '|>\n' .. msg.content)
  end

  if vim.tbl_get(contents.messages, #contents.messages, 'role') ~= 'assistant' then
    table.insert(result, '\n<|assistant|>\n')
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
---@return string[]
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
    local tokens_list = {
      {BOS}
    }

    for _,msg in ipairs(formatted_messages) do
      local tokens = wait(tokenize(msg, url_, resolve))

      table.insert(tokens, EOS)
      table.insert(tokens_list, tokens)
    end

    local tail = wait(tokenize('<|assistant|>\n', url_, resolve))
    table.insert(tokens_list, tail)

    return vim.tbl_flatten(tokens_list)
  end, cb)
end

M.run = {}

---Tokenizes each message individually and adds a 2 (EOS) token between messages.
function M.run.tokenize(contents)
  return function(config)
    async(function(wait, resolve)
      if contents.config.options.server_start then
        wait(llamacpp.start_server(contents.config.options.server_start, resolve))
      end

      zephyr.tokenize(contents, nil, function(tokens)
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

---Converts contents to a single string with </s> between messages, and
---uses </s> as a stop. </s> should be the stop token (2) but gets tokenized
---as a normal string.
---May produce different results than when tokenizing messages individually
---and using an actual EOS token.
function M.run.strings_with_stop(contents)
  return vim.tbl_deep_extend('force', contents.config, {
    params = {
      prompt = M.from_chat_contents(contents),
      stop = {
        '</s>'
      }
    }
  })
end

return M
