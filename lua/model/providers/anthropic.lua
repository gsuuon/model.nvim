local model = require('model')
local util = require('model.util')
local sse = require('model.util.sse')
local tools_handler = require('model.tools.handler')

---@param tools table<string, Tool>
local function format_tool_definitions(tools)
  local formatted = {}
  for name, tool in pairs(tools) do
    table.insert(formatted, {
      name = name,
      description = tool.description,
      input_schema = tool.parameters,
    })
  end

  return formatted
end

--- Anthropic provider
--- options:
--- {
---   headers: table,
---   trim_code?: boolean -- streaming trim leading newline and trailing codefence
---   tools?: boolean | string []
--- }
---@class Provider
local M = {
  request_completion = function(handler, params, options)
    options = options or {}

    local consume = handler.on_partial
    local finish = function() end

    if options.trim_code then
      -- we keep 1 partial in buffer so we can strip the leading newline and trailing markdown block fence
      local last = nil

      ---@param partial string
      consume = function(partial)
        if last then
          handler.on_partial(last)
          last = partial
        else -- strip the first leading newline
          last = partial:gsub('^\n', '')
        end
      end

      finish = function()
        if last then
          -- ignore the trailing codefence
          handler.on_partial(last:gsub('\n```$', ''))
        end
      end
    end

    if options.tools then
      local tool_handler = tools_handler.tool(model.opts.tools, options.tools)
      local tool_uses = tool_handler.get_uses(params)

      if next(tool_uses) ~= nil then
        return tool_handler.run(tool_uses, handler.on_finish)
      end

      params.tools = format_tool_definitions(tool_handler.get_equipped_tools())
    end

    params.messages = vim.tbl_map(function(msg)
      local message = {
        role = msg.role,
        content = {},
      }

      if msg.content ~= nil and vim.trim(msg.content) ~= '' then
        if msg.content:match('^>> cache\n') then
          table.insert(message.content, {
            type = 'text',
            text = msg.content:gsub('^>> cache\n', ''),
            cache_control = {
              type = 'ephemeral',
            },
          })
        else
          table.insert(message.content, {
            type = 'text',
            text = msg.content,
          })
        end
      end

      for _, section in ipairs(msg.data_sections or {}) do
        if msg.role == 'user' then
          local tool_id = section.label:match('^tool_result: (.+)$')

          if tool_id then
            table.insert(message.content, {
              type = 'tool_result',
              tool_use_id = tool_id,
              content = section.content,
            })
          else
            util.eshow(section, 'Unexpected data section in chat')
          end
        elseif section.label == 'tool_calls' then
          local tool_calls = util.json.decode(section.content)

          for _, tool_call in ipairs(tool_calls or {}) do
            table.insert(message.content, {
              type = 'tool_use',
              id = tool_call.id,
              name = tool_call.name,
              input = util.json.decode(tool_call.arguments),
            })
          end
        end
      end
      util.show(msg)
      util.show(message)

      return message
    end, params.messages)

    local tool_chunk_handler = tools_handler.chunk(handler.on_partial)

    return sse.curl_client({
      url = 'https://api.anthropic.com/v1/messages',
      headers = vim.tbl_extend('force', {
        ['Content-Type'] = 'application/json',
        ['x-api-key'] = util.env('ANTHROPIC_API_KEY'),
        ['anthropic-beta'] = 'messages-2023-12-15',
        ['anthropic-version'] = '2023-06-01',
      }, options.headers or {}),
      body = util.tap_if(
        vim.tbl_deep_extend('force', {
          max_tokens = 1024, -- required field
        }, params, { stream = true }),
        options.debug
      ),
    }, {
      on_message = function(msg)
        local data = util.json.decode(msg.data)

        if msg.event == 'content_block_delta' then
          if data and data.delta then
            if data.delta.type == 'text_delta' then
              consume(data.delta.text)
            elseif data.delta.type == 'input_json_delta' then
              tool_chunk_handler.arg_partial(data.delta.partial_json)
            end
          end
        elseif msg.event == 'message_delta' then
          util.show(data.usage.output_tokens, 'output tokens')
        elseif msg.event == 'message_stop' then
          finish()
        elseif msg.event == 'content_block_start' then
          if
            data
            and data.content_block
            and data.content_block.type == 'tool_use'
          then
            tool_chunk_handler.new_call(
              data.content_block.name,
              data.content_block.id
            )
          end
        end
      end,
      on_error = handler.on_error,
      on_other = handler.on_error,
      on_exit = function()
        tool_chunk_handler.finish()
        handler.on_finish()
      end,
    })
  end,
}

---@deprecated Anthropic provider always does this now
---@param content string
M.cache_if_prefixed = function(content)
  return content
end

return M
