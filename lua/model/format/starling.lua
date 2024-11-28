return {
  ---@param messages ChatMessage[]
  ---@param config ChatConfig
  chat = function(messages, config)
    if #messages < 1 then
      error('Need at least one message')
    end

    local first_msg = messages[1]
    local prompt = 'GPT4 Correct User: '
      .. (config.system and config.system .. '\n' or '')
      .. first_msg.content
      .. '<|end_of_turn|>'

    for i, msg in ipairs(messages) do
      if i > 1 then
        prompt = prompt
          .. (msg.role == 'user' and 'GPT4 Correct User:' or 'GPT4 Correct Assistant:')
          .. msg.content
          .. '<|end_of_turn|>'
      end
    end

    prompt = prompt .. 'GPT4 Correct Assistant: '

    return {
      prompt = prompt,
      raw = true,
    }
  end,
}
