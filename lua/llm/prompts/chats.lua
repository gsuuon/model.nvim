local openai = require('llm.providers.openai')

local chat_openai = {
  provider = openai,
  contents = {
    system = 'You are a helpful assistant',
    config = {
      model = 'gpt-3.5-turbo-1106'
    }
  },
  create = function(input, context)
    return {
      messages = {
        {
          role = 'user',
          content = input
        }
      }
    }
  end,
  run = function(contents)
    local params = contents.config or {}
    params.messages = contents.messages

    if contents.system then
      table.insert(params.messages, 1, {
        role = 'system',
        content = contents.system
      })
    end

    return { params = params }
  end
}

---@type table<string, ChatPrompt>
local chats = {
  openai = chat_openai,
  gpt4 = vim.tbl_deep_extend(
    'force',
    chat_openai,
    {
      contents = {
        config = {
          model = 'gpt-4-1106-preview',
        }
      }
    }
  )
}

return chats
