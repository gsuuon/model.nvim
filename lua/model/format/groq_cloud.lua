return {
  ---@param messages ChatMessage[]
  ---@param config ChatConfig
  chat = function(messages, config)
    -- if there's a system message, append it to the beginning
    if config.system then
      return {
        messages = {
          {
            content = config.system,
            role = 'system',
          },
          unpack(messages),
        },
      }
    else
      return {
        messages = messages,
      }
    end
  end,
}
