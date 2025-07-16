local model = require('model')
local util = require('model.util')
local sse = require('model.util.sse')
local tools_handler = require('model.tools.handler')
local juice = require('model.util.juice')
local format = require('model.format.openai')

-- Response extraction utilities
local function extract_chunk(data)
  if not (data and data.choices and data.choices[1]) then
    return
  end

  local choice = data.choices[1]
  return {
    content = choice.delta.content,
    reasoning_content = choice.delta.reasoning_content,
    finish_reason = choice.finish_reason,
    tool_calls = choice.delta.tool_calls,
  }
end

-- Reasoning content management
local REASONING_DELIM_START = '<<<<<< reasoning\n'
local REASONING_DELIM_STOP = '\n>>>>>>\n'

local function create_reason_handler(handler, show_reasoning)
  local is_reasoning = false

  local reason_count = 0

  if show_reasoning then
    return {
      reason = function(partial)
        if not is_reasoning then
          is_reasoning = true
          handler.on_partial(REASONING_DELIM_START .. partial)
        else
          handler.on_partial(partial)
        end
      end,
      content = function(partial)
        if is_reasoning then
          is_reasoning = false
          handler.on_partial(REASONING_DELIM_STOP .. partial)
        else
          handler.on_partial(partial)
        end
      end,
      finish = function(complete_text, finish_reason)
        if is_reasoning then
          handler.on_partial(REASONING_DELIM_STOP)
        end
        handler.on_finish(complete_text, finish_reason)
      end,
      stop = util.noop,
    }
  else
    local stop_marquee = util.noop
    local update_marquee = util.noop
    local spinner_segment = { data = {} }

    return {
      reason = function(partial)
        if is_reasoning then
          reason_count = reason_count + 1
          spinner_segment.data.info = spinner_segment.data.info .. partial
          update_marquee(
            'Thinking.. (' .. tostring(reason_count) .. ' thoughts)'
          )
        else
          is_reasoning = true
          handler.on_partial('') -- to stop the 'waiting' spinner, we have a response

          stop_marquee, update_marquee, spinner_segment =
            juice.spinner(handler.segment, 'Thinking ')

          spinner_segment.data.info = partial or ''
          spinner_segment.data.cancel = stop_marquee
        end
      end,
      content = function(partial)
        if is_reasoning then
          is_reasoning = false
          stop_marquee()
        end

        handler.on_partial(partial)
      end,
      finish = handler.on_finish,
      stop = function()
        stop_marquee()
      end,
    }
  end
end

-- Message processing helpers
local function set_prefix_field_on_last_message(params)
  params.messages[#params.messages].prefix = true
end

local function ends_with_assistant_message(params)
  local messages = params.messages
  return messages and #messages > 0 and messages[#messages].role == 'assistant'
end

-- Deepseek provider implementation
local M = {
  ---@param handler StreamHandlers
  request_completion = function(handler, params, options)
    options = options or {}

    local is_prefix_completion = ends_with_assistant_message(params)
    -- NOTE prefix is incompatible with tool use, but not sure if prefix should be discarded or tool use disabled
    -- for now, we just allow it to error

    local url = options.url
      or (
        is_prefix_completion
          and 'https://api.deepseek.com/beta/chat/completions'
        or 'https://api.deepseek.com/chat/completions'
      )

    local reason_handler =
      create_reason_handler(handler, options.show_reasoning)

    local function on_other(msg)
      reason_handler.stop()

      -- most likely an error
      handler.on_error(msg)
    end

    local function on_error(err)
      reason_handler.stop()
      handler.on_error(err)
    end

    local tool_handler = tools_handler.tool(model.opts.tools, options.tools)
    local tool_chunk_handler =
      tools_handler.chunk(handler.on_partial, tool_handler.get_equipped_tools())

    local function on_message(msg, raw)
      local data = util.json.decode(msg.data)
      local chunk = extract_chunk(data)

      if not chunk then
        if msg.data ~= '[DONE]' then
          util.eshow(raw, 'Extracted empty chunk')
        end
        return
      end

      if chunk.reasoning_content then
        reason_handler.reason(chunk.reasoning_content)
      elseif chunk.finish_reason then
        tool_chunk_handler.finish()
        reason_handler.finish(nil, chunk.finish_reason)
      elseif chunk.content then
        reason_handler.content(chunk.content)
      elseif chunk.tool_calls then
        for _, tool_call_partial in ipairs(chunk.tool_calls) do
          if tool_call_partial['function'] then
            local fn = tool_call_partial['function']

            if tool_call_partial.id and fn.name then
              tool_chunk_handler.new_call(fn.name, tool_call_partial.id)
            end

            if fn.arguments then
              tool_chunk_handler.arg_partial(fn.arguments)
            end
          end
        end
      end
    end

    if options.tools then
      local tool_uses = tool_handler.get_uses(params)

      if next(tool_uses) ~= nil then
        return tool_handler.run(tool_uses, function(result)
          reason_handler.stop()
          handler.on_finish(result)
        end)
      end

      params.tools =
        format.build_tool_definitions(tool_handler.get_equipped_tools())
    end

    params.messages = format.transform_messages(params.messages)

    if is_prefix_completion then
      set_prefix_field_on_last_message(params)
    end

    if options.debug then
      util.show(params)
    end

    handler.segment.data.params = params

    return sse.curl_client({
      url = url,
      method = 'POST',
      headers = {
        ['Content-Type'] = 'application/json',
        ['Authorization'] = options.authorization
          or ('Bearer ' .. util.env('DEEPSEEK_API_KEY')),
      },
      body = vim.tbl_deep_extend('force', params, { stream = true }),
    }, {
      on_message = on_message,
      on_error = on_error,
      on_other = on_other,
    })
  end,

  ---@deprecated handled by chat parse
  strip_asst_messages_of_reasoning = function(body)
    return body
  end,
}

return M
