local openai = require('model.providers.openai')
local palm = require('model.providers.palm')
local llamacpp = require('model.providers.llamacpp')
local ollama = require('model.providers.ollama')

local zephyr_fmt = require('model.format.zephyr')
local starling_fmt = require('model.format.starling')

local function input_if_selection(input, context)
  return context.selection and input or ''
end

local chat_openai = {
  provider = openai,
  system = 'You are a helpful assistant',
  params = {
    model = 'gpt-3.5-turbo-1106'
  },
  create = input_if_selection,
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
    create = input_if_selection,
    run = zephyr_fmt.chat
  },
  starling = {
    provider = ollama,
    params = {
      model = 'starling-lm'
    },
    create = input_if_selection,
    run = starling_fmt.chat
  },
  palm = {
    provider = palm,
    system = 'You are a helpful assistant',
    create = input_if_selection,
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
