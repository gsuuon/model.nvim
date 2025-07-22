local util = require('model.util')
local util_tools = require('model.util.tools')

-- Tool handling utilities
local TOOL_CALL_DELIM = '\n<<<<<< tool_calls\n'
local TOOL_CALL_DELIM_END = '\n>>>>>>\n'

-- Emits tool calls in a data_section with contents as JSON encoded of type ToolCall
local function create_tool_chunk_handlers(emit, equipped_tools)
  local has_tool_calls = false
  local active_tool_json_stream = nil

  return {
    ---@param name string
    ---@param id string
    new_call = function(name, id)
      if not has_tool_calls then
        has_tool_calls = true
        -- the newline before is necessary, sometimes we already have several -- would be nice to skip this if we do to avoid unecessary ugly spacing
        emit(TOOL_CALL_DELIM)
        emit('[\n')
      else
        emit('"\n  },\n')
      end

      emit(([[
  {
    "id": "%s",
    "name": "%s",
    "arguments": "]]):format(id, name))

      local tool = equipped_tools[name]
      if tool and tool.presentation then
        active_tool_json_stream = tool.presentation()
      end
    end,
    arg_partial = function(partial)
      local escaped = partial
        :gsub('\\', '\\\\')
        :gsub('"', '\\"')
        :gsub('\n', '\\n')
        :gsub('\r', '\\r')
        :gsub('\t', '\\t')

      emit(escaped)

      if active_tool_json_stream then
        local consumed_offset = active_tool_json_stream(partial)

        if consumed_offset and consumed_offset ~= #partial then
          util.eshow(
            'Finished handling json object but there was more left. Consumed: '
              .. consumed_offset
              .. ', Partial: '
              .. #partial
          )
        end
      end
    end,
    finish = function()
      if has_tool_calls then
        emit('"\n  }\n]' .. TOOL_CALL_DELIM_END)
      end
    end,
  }
end

---@param available_tools table<string, table> Map of available tool names to their definitions
---@param allowed_tools string[] | boolean An allowlist of tools, or true for all, or falsy for none
local function create_tool_handler(available_tools, allowed_tools)
  local equipped_tools = util_tools.equip_tools(available_tools, allowed_tools)

  local function run_tool(tool_uses, on_finish)
    if next(tool_uses) ~= nil then
      local results = {}
      local cancels = {}
      local finished = 0
      local total = 0
      local complete = false

      for _ in pairs(tool_uses) do
        total = total + 1
      end

      local function maybe_finish()
        if not complete and finished == total then
          complete = true

          local result_strings = {}

          for id, content in pairs(results) do
            table.insert(
              result_strings,
              string.format(
                '<<<<<< tool_result: %s\n%s\n>>>>>>',
                id,
                type(content) == 'string' and content
                  or vim.json.encode(content)
              )
            )
          end

          on_finish(table.concat(result_strings, '\n'))
        end
      end

      local status_messages = {}

      for id, closure in pairs(tool_uses) do
        local function on_tool_done(result, err)
          if err ~= nil then
            results[id] = 'Tool call failed. Error: ' .. tostring(err)
          else
            results[id] = result == nil and 'nil' or result
          end
          finished = finished + 1

          if status_messages[id] ~= nil then
            util.show('Done: ' .. status_messages[id])
          end

          maybe_finish()
        end

        local ok, ret, msg = pcall(function()
          return closure(on_tool_done)
        end)

        if ok then
          if type(ret) == 'function' then
            if msg then
              status_messages[id] = msg
              util.show('Started: ' .. msg)
            end
            table.insert(cancels, ret)
          else
            results[id] = ret == nil and 'nil' or ret
            finished = finished + 1
            maybe_finish()
          end
        else
          results[id] = 'Error: ' .. tostring(ret)
          finished = finished + 1
          maybe_finish()
        end
      end

      return function()
        for _, cancel in ipairs(cancels) do
          pcall(cancel)
        end
      end
    end
  end

  local function get_uses(params)
    local last_msg = params.messages[#params.messages]
    local tool_uses = {}

    if last_msg and last_msg.role == 'assistant' and last_msg.data_sections then
      for _, section in ipairs(last_msg.data_sections) do
        if section.label == 'tool_calls' then
          local section_tool_calls = util.json.decode(section.content)

          for _, tool_call in ipairs(section_tool_calls or {}) do
            local tool_name = tool_call.name
            local tool = equipped_tools[tool_name]

            if tool then
              tool_uses[tool_call.id] = function(resolve)
                if tool_call.arguments == '' then
                  return tool.invoke({}, resolve)
                else
                  local args, err = util.json.decode(tool_call.arguments)

                  if args then
                    return tool.invoke(args, resolve)
                  else
                    error(err)
                  end
                end
              end
            else
              util.eshow('Unknown tool: ' .. tool_name)
            end
          end
        end
      end
    end

    return tool_uses
  end

  return {
    run = run_tool,
    get_uses = get_uses,
    get_equipped_tools = function()
      return equipped_tools
    end,
  }
end

return {
  tool = create_tool_handler,
  chunk = create_tool_chunk_handlers,
}
