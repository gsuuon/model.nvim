local llamacpp = require('model.providers.llamacpp')

-- NOTE: llamacpp may be handling text that matches stop tokens itself now? it seems to be stopping correctly with just '</s>' text between turns instead of spitting out </s>.

local util = require('model.util')
local curl = require('model.util.curl')
local async = require('model.util.async')

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
---@param messages ChatMessage[]
---@param system string
---@param url_base string
---@param cb fun(tokens: number[]): any
local function tokenize_messages(messages, system, url_base, cb)
  local BOS = 1
  local EOS = 2

  local formatted_messages = contents_to_strings(messages, system)

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
---@param messages ChatMessage[]
---@param config table
function M.chatprompt_tokenize_run(messages, config)
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

      util.show(#tokens, '#tokens')

      set_params({
        prompt = tokens
      })
    end)
  end
end
