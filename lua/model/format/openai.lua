local util = require('model.util')

---@param message ChatMessage
local function transform_data_section(message)
  local results = {}
  if message.role == 'user' then
    for _, section in ipairs(message.data_sections or {}) do
      local tool_id = section.label:match('^tool_result: (.+)$')
      if tool_id then
        table.insert(results, {
          role = 'tool',
          tool_call_id = tool_id,
          content = section.content,
        })
      end
    end

    if vim.trim(message.content) ~= '' then
      table.insert(results, {
        role = 'user',
        content = message.content,
      })
    end
  elseif message.role == 'assistant' then
    local assistant_message = {
      role = 'assistant',
      content = message.content or '',
    }

    for _, section in ipairs(message.data_sections or {}) do
      if section.label == 'tool_calls' then
        local tool_calls = util.json.decode(section.content)
        if tool_calls then
          if assistant_message.tool_calls == nil then
            assistant_message.tool_calls = {}
          end

          for _, tool_call in ipairs(tool_calls) do
            table.insert(assistant_message.tool_calls, {
              id = tool_call.id,
              type = 'function',
              ['function'] = {
                name = tool_call.name,
                arguments = tool_call.arguments,
              },
            })
          end
        end
      end
    end

    table.insert(results, assistant_message)
  else
    table.insert(results, message)
  end

  return results
end

local function transform_messages(messages)
  local transformed = {}
  for _, message in ipairs(messages) do
    local results = transform_data_section(message)
    for _, result in ipairs(results) do
      table.insert(transformed, result)
    end
  end
  return transformed
end

local function build_tool_definitions(equipped_tools)
  local list = {}

  for tool_name, tool in pairs(equipped_tools) do
    table.insert(list, {
      type = 'function',
      ['function'] = {
        name = tool_name,
        description = tool.description,
        parameters = tool.parameters,
      },
    })
  end

  return list
end

return {
  transform_data_section = transform_data_section,
  transform_messages = transform_messages,
  build_tool_definitions = build_tool_definitions,
}
