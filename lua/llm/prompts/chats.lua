local openai = require('llm.providers.openai')

---@type table<string, ChatPrompt>
local chats = {
  openai = {
    provider = openai,
    create = function(input, context)
      return {
        system = 'You are a helpful assistant',
        config = {
          model = 'gpt-3.5-turbo-1106'
        },
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
}

return chats
