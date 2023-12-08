local openai = require('model.providers.openai')
local palm = require('model.providers.palm')
local zephyr_fmt = require('model.format.zephyr')
local llamacpp = require('model.providers.llamacpp')

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
        '-c', 8192,
        '-ngl', 35
      }
    },
    system = 'You are a helpful assistant',
    create = function(input, context)
      return context.selection and input or ''
    end,
    run = function(messages, config)
      return {
        prompt = zephyr_fmt.content_to_prompt(messages, config)
      }
    end
  },
  palm = {
    provider = palm,
    system = 'You are a helpful assistant',
    create = function(input, context)
      return context.selection and input or ''
    end,
    options = {
      method = 'generateMessage',
      model = 'chat-bison-001'
    },
    run = function(messages, config)
      return {
        prompt = {
          context = config.system,
          messages = vim.tbl_map(function(msg)
            return {
              content = msg.content,
              author = msg.role
            }
          end, messages)
        }
      }
    end
  }
}

return chats
