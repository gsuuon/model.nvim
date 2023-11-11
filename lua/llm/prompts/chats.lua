local util = require('llm.util')
local openai = require('llm.providers.openai')

---@type table<string, ChatPrompt>
local chats = {
  openai = {
    provider = openai,
    create = function(input, context)
      return {
        system = 'You are a helpful assistant',
        config = {
          model = 'gpt-3.5-turbo'
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
      local messages = {}

      -- TODO params and options
      local config = util.table.without(contents.config, 'chat')

      if contents.system then
        table.insert(messages, {
          role = 'system',
          content = contents.system
        })
      end

      for _,msg in ipairs(contents.messages) do
        table.insert(messages, msg)
      end

      config.messages = messages

      return {
        params = config
      }
    end
  }
}

return chats
