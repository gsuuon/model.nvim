local util = require('model.util')

-- Tool handling utilities
local TOOL_CALL_DELIM = '<<<<<< tool_calls\n'
local TOOL_CALL_DELIM_END = '\n>>>>>>'

local function create_tool_chunk_handlers(emit)
  local has_tool_calls = false

  return {
    ---@param name string
    ---@param id string
    new_call = function(name, id)
      if not has_tool_calls then
        has_tool_calls = true
        -- the newline before is necessary, sometimes we already have several -- would be nice to skip this if we do to avoid unecessary ugly spacing
        emit('\n' .. TOOL_CALL_DELIM .. '[\n')
      else
        emit('"\n  },\n')
      end

      emit(([[
  {
    "id": "%s",
    "name": "%s",
    "arguments": "]]):format(id, name))
    end,
    arg_partial = function(partial)
      emit(
        partial
          :gsub('\\', '\\\\')
          :gsub('"', '\\"')
          :gsub('\n', '\\n')
          :gsub('\r', '\\r')
          :gsub('\t', '\\t')
      )
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
  ---@type table<string, Tool>
  local equipped_tools = {}
  do
    if allowed_tools == nil or type(allowed_tools) == 'boolean' then
      if allowed_tools == true then
        for tool_name in util.module.autopairs(available_tools) do
          equipped_tools[tool_name] = available_tools[tool_name]
        end
      else
        -- allowed_tools is falsy, so we just provide no-op handlers
        -- these handlers are weaved into the handlers the provider builds so always need to be available
        return {
          partial = util.noop,
          finish = util.noop,
        }
      end
    else
      if vim.islist(allowed_tools) then
        for _, tool_name in pairs(allowed_tools) do
          if available_tools[tool_name] then
            equipped_tools[tool_name] = available_tools[tool_name]
          else
            util.eshow('Missing tool: ' .. tool_name)
          end
        end
      end
    end
  end

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
          local result_str = ''
          for id, content in pairs(results) do
            result_str = result_str
              .. string.format(
                '\n<<<<<< tool_result: %s\n%s\n>>>>>>\n',
                id,
                type(content) == 'string' and content
                  or vim.json.encode(content)
              )
          end
          on_finish(result_str)
        end
      end

      for id, closure in pairs(tool_uses) do
        local function on_tool_done(result, err)
          if err ~= nil then
            results[id] = 'Error: ' .. tostring(err)
          else
            results[id] = result == nil and 'nil' or result
          end
          finished = finished + 1
          maybe_finish()
        end

        local ok, ret = pcall(function()
          return closure(on_tool_done)
        end)

        if ok then
          if type(ret) == 'function' then
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
    local tool_queue = {}

    if last_msg and last_msg.role == 'assistant' and last_msg.data_sections then
      for _, section in ipairs(last_msg.data_sections) do
        if section.label == 'tool_calls' then
          local tool_calls = util.json.decode(section.content)

          for _, tool_call in ipairs(tool_calls or {}) do
            local tool_name = tool_call.name
            local tool = equipped_tools[tool_name]

            if tool then
              tool_queue[tool_call.id] = function(resolve)
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

    return tool_queue
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
