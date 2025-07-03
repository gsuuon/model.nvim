local util = require('model.util')

-- Tool handling utilities
local TOOL_CALL_DELIM = '<<<<<< tool_calls\n```js\n'
local TOOL_CALL_DELIM_END = '\n```\n>>>>>>'

local function create_tool_handler(request_handlers, available_tools)
  local tool_calls = {}
  local has_tool_calls = false
  local current_index = nil

  local function init_tool_call(call)
    if not has_tool_calls then
      has_tool_calls = true
      request_handlers.on_partial('\n' .. TOOL_CALL_DELIM .. '[\n')
    else
      request_handlers.on_partial('"\n    }\n  },\n')
    end

    request_handlers.on_partial(('  {\n    "id": "%s",\n'):format(call.id))
    request_handlers.on_partial(('    "type": "%s",\n'):format(call.type))
    request_handlers.on_partial('    "function": {\n')
    request_handlers.on_partial(
      ('      "name": "%s",\n'):format(call['function'].name)
    )
    request_handlers.on_partial('      "arguments": "')
  end

  local function run_tool(tool_uses)
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
          request_handlers.on_finish(result_str)
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

    if last_msg and last_msg.role == 'assistant' and last_msg.tool_calls then
      for _, tool_call in ipairs(last_msg.tool_calls) do
        local tool_name = tool_call['function'].name
        local tool = available_tools[tool_name]

        if tool then
          tool_queue[tool_call.id] = function(resolve)
            local args, err = util.json.decode(tool_call['function'].arguments)
            if args then
              return tool.invoke(args, resolve)
            else
              return nil, err
            end
          end
        else
          util.eshow('Unknown tool: ' .. tool_name)
        end
      end
    end

    return tool_queue
  end

  local function transform_messages(params)
    local transformed = {}

    for _, msg in ipairs(params.messages) do
      if msg.role == 'assistant' then
        local content = msg.content or ''
        local pattern = TOOL_CALL_DELIM .. '(.-)' .. TOOL_CALL_DELIM_END
        local tool_block = content:match(pattern)

        if tool_block then
          local parsed, err = util.json.decode(tool_block)
          if parsed then
            local updated = {
              content = content:gsub(
                TOOL_CALL_DELIM .. '.-' .. TOOL_CALL_DELIM_END,
                ''
              ),
              tool_calls = parsed,
            }
            table.insert(
              transformed,
              vim.tbl_deep_extend('force', msg, updated)
            )
          else
            util.eshow(err, 'Tool block failed to parse')
            table.insert(transformed, msg)
          end
        else
          table.insert(transformed, msg)
        end
      else
        local content = msg.content or ''
        local tool_results = {}

        local clean_content = content:gsub(
          '<<<<<< tool_result: (%S+)\n(.-)\n>>>>>>',
          function(id, result)
            table.insert(tool_results, {
              role = 'tool',
              tool_call_id = id,
              content = result,
            })
            return ''
          end
        )

        if #tool_results > 0 then
          for _, res in ipairs(tool_results) do
            table.insert(transformed, res)
          end
          if clean_content ~= '' then
            table.insert(
              transformed,
              vim.tbl_extend('keep', msg, { content = clean_content })
            )
          end
        else
          table.insert(transformed, msg)
        end
      end
    end

    -- Show warning if tool_results is immediately followed by an assistant message
    if #transformed >= 2 then
      local last = transformed[#transformed]
      local prev = transformed[#transformed - 1]
      if
        last.role == 'assistant'
        and prev.role == 'tool'
        and last.tool_calls == nil
      then
        util.show(
          'Warning: Tool use with a trailing assistant message is probably not supported. '
            .. 'You can add your response to tool_results directly in the same message as the tool_block section.'
        )
      end
    end

    if available_tools and next(available_tools) ~= nil then
      local tool_list = {}

      for tool_name, tool in util.module.autopairs(available_tools) do
        table.insert(tool_list, {
          type = 'function',
          ['function'] = {
            name = tool_name,
            description = tool.description,
            parameters = tool.parameters,
          },
        })
      end
      params.tools = tool_list
    end

    params.messages = transformed
    return params
  end

  return {
    partial = function(chunk_tool_calls)
      for _, tool_call_partial in ipairs(chunk_tool_calls) do
        local index = tool_call_partial.index or 0
        local call = tool_call_partial

        if not tool_calls[index + 1] then
          tool_calls[index + 1] = {
            id = call.id or '',
            type = call.type or 'function',
            ['function'] = {
              name = call['function'] and call['function'].name or '',
              arguments = call['function'] and call['function'].arguments or '',
            },
          }
          current_index = index + 1
          init_tool_call(tool_calls[current_index])
        end

        if call['function'] and call['function'].arguments then
          local escaped = call['function'].arguments
            :gsub('\\', '\\\\')
            :gsub('"', '\\"')
            :gsub('\n', '\\n')
            :gsub('\r', '\\r')
            :gsub('\t', '\\t')

          tool_calls[current_index]['function'].arguments = tool_calls[current_index]['function'].arguments
            .. escaped
          request_handlers.on_partial(escaped)
        end
      end
    end,
    finish = function()
      if has_tool_calls then
        request_handlers.on_partial(
          '"\n    }\n  }\n]' .. TOOL_CALL_DELIM_END .. '\n'
        )
      end
    end,
    run = run_tool,
    get_uses = get_uses,
    transform_messages = transform_messages,
  }
end

return {
  create = create_tool_handler,
  noop = {
    partial = util.noop,
    finish = util.noop,
  },
}
