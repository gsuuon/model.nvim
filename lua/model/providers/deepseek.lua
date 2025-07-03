local model = require('model')
local util = require('model.util')
local sse = require('model.util.sse')
local tools_handler = require('model.tools.handler')
local juice = require('model.util.juice')

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

local function strip_reasoning(text)
  local start_pos, end_pos =
    text:find(REASONING_DELIM_START .. '.-' .. REASONING_DELIM_STOP)

  return start_pos and text:sub(1, start_pos - 1) .. text:sub(end_pos + 1)
    or text
end

local function create_reason_handler(handler, show_reasoning)
  local is_reasoning = false

  local stop_marquee = juice.spinner(handler.segment, 'Waiting for a response')

  local update_marquee = function(_) end
  local reason_count = 0

  if show_reasoning then
    return {
      reason = function(partial)
        stop_marquee()
        if not is_reasoning then
          is_reasoning = true
          handler.on_partial(REASONING_DELIM_START .. partial)
        else
          handler.on_partial(partial)
        end
      end,
      content = function(partial)
        stop_marquee()
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
    }
  else
    return {
      reason = function()
        if is_reasoning then
          reason_count = reason_count + 1
          update_marquee('Thinking (' .. tostring(reason_count) .. ' thoughts)')
        else
          stop_marquee()
          is_reasoning = true
          stop_marquee, update_marquee =
            juice.spinner(handler.segment, 'Thinking ')
        end
      end,
      content = function(partial)
        if is_reasoning then
          is_reasoning = false
        end

        stop_marquee()
        handler.on_partial(partial)
      end,
      finish = handler.on_finish,
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

    if is_prefix_completion then
      set_prefix_field_on_last_message(params)
    end

    local tool_handler
    do
      if options.enable_tools then
        tool_handler = tools_handler.create(handler, model.opts.tools)
        tool_handler.transform_messages(params)

        local tool_uses = tool_handler.get_uses(params)

        if next(tool_uses) ~= nil then
          return tool_handler.run(tool_uses)
        end
      else
        tool_handler = tools_handler.noop
      end
    end

    local reason_handler =
      create_reason_handler(handler, options.show_reasoning)

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
      on_message = function(msg)
        local data = util.json.decode(msg.data)
        local chunk = extract_chunk(data)
        if not chunk then
          if msg.data ~= '[DONE]' then
            util.eshow(msg, 'Extracted chunk was empty')
          end

          return
        end

        if chunk.reasoning_content then
          reason_handler.reason(chunk.reasoning_content)
        elseif chunk.finish_reason then
          tool_handler.finish()
          reason_handler.finish(nil, chunk.finish_reason)
        elseif chunk.content then
          reason_handler.content(chunk.content)
        elseif chunk.tool_calls then
          tool_handler.partial(chunk.tool_calls)
        end
      end,
      on_error = handler.on_error,
      on_other = util.show,
    })
  end,

  strip_asst_messages_of_reasoning = function(body)
    return vim.tbl_deep_extend('force', body, {
      messages = vim.tbl_map(function(msg)
        if msg.role == 'assistant' then
          return vim.tbl_extend('keep', msg, {
            content = strip_reasoning(msg.content or ''),
          })
        end
        return msg
      end, body.messages),
    })
  end,
}

return M
