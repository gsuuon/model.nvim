local openai = require('llm.providers.openai')
local zephyr = require('llm.format.zephyr')
local llamacpp = require('llm.providers.llamacpp')

local chat_openai = {
  provider = openai,
  system = 'You are a helpful assistant',
  params = {
    model = 'gpt-3.5-turbo-1106'
  },
  create = function(input, context)
    return context.selection and input or ''
  end,
  run = function(messages, config)
    if config.system then
      table.insert(messages, 1, {
        role = 'system',
        content = config.system
      })
    end

    return { messages = messages }
  end
}

---@type table<string, ChatPrompt>
local chats = {
  openai = chat_openai,
  gpt4 = vim.tbl_deep_extend(
    'force',
    chat_openai,
    {
      params = {
        model = 'gpt-4-1106-preview',
      }
    }
  ),
  zephyr = {
    provider = llamacpp,
    options = {
      model = 'zephyr-7b-beta.Q5_K_M.gguf',
      args = {
        '-c', 4096,
        '-ngl', 24
      }
    },
    system = 'You are a helpful assistant',
    create = function(input, context)
      return context.selection and input or ''
    end,
    run = zephyr.chatprompt_run
  }
}

return chats
