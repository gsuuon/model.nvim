local util = require('model.util')
local sse = require('model.util.sse')

local function extract(data)
  if data == nil or data.choices == nil or data.choices[1] == nil then
    return
  end

  return {
    content = data.choices[1].delta.content,
    reasoning_content = data.choices[1].delta.reasoning_content,
    finish_reason = data.choices[1].finish_reason,
  }
end

local reasoning_delimit_start = '<<<<<< reasoning\n'
local reasoning_delimit_stop = '\n>>>>>>\n'

local function strip_reasoning(text)
  -- Find the start and end positions of the reasoning block
  local start_pos, end_pos =
    text:find(reasoning_delimit_start .. '.-' .. reasoning_delimit_stop)

  -- If the reasoning block is found, remove it from the text
  if start_pos and end_pos then
    return text:sub(1, start_pos - 1) .. text:sub(end_pos + 1)
  end

  -- If no reasoning block is found, return the original text
  return text
end

---@param handler StreamHandlers
local function reason_shown(handler)
  local is_reasoning = false

  return {
    reason = function(partial)
      if is_reasoning then
        handler.on_partial(partial)
      else
        is_reasoning = true
        handler.on_partial(reasoning_delimit_start .. partial)
      end
    end,
    content = function(partial)
      if is_reasoning then
        is_reasoning = false
        handler.on_partial(reasoning_delimit_stop .. partial)
      else
        handler.on_partial(partial)
      end
    end,
    finish = handler.on_finish,
  }
end

---@param handler StreamHandlers
local function reason_hidden(handler)
  local is_reasoning = false

  return {
    reason = function()
      if not is_reasoning then
        is_reasoning = true
        util.show('Reasoning..')
      end
    end,
    content = handler.on_partial,
    finish = handler.on_finish,
  }
end

local function set_prefix_field_on_last_message(params)
  params.messages[#params.messages].prefix = true
end

local function ends_with_assistant_message(params)
  return params.messages ~= nil
    and #params.messages > 0
    and params.messages[#params.messages].role == 'assistant'
end

--- Deepseek provider
--- Adds reasoning content into responses and strips them from inputs in conversations.
--- Switches to the beta if the last message is an assistant message (prefix completion)
--- https://api-docs.deepseek.com/guides/chat_prefix_completion
---
--- options:
--- {
---   show_reasoning: boolean
---   url: string
---   authorization: string
--- }
---@class Provider
local M = {
  request_completion = function(handler, params, options)
    local options = options or {}
    local handle = options.show_reasoning and reason_shown(handler)
      or reason_hidden(handler)

    local is_prefix_completion = ends_with_assistant_message(params)

    local url = options.url
      or (
        is_prefix_completion
          and 'https://api.deepseek.com/beta/chat/completions'
        or 'https://api.deepseek.com/chat/completions'
      )

    if is_prefix_completion then
      set_prefix_field_on_last_message(params)
    end

    return sse.curl_client({
      url = url,
      method = 'POST',
      headers = vim.tbl_extend('force', {
        ['Content-Type'] = 'application/json',
        ['Authorization'] = options.authorization
          or ('Bearer ' .. util.env('DEEPSEEK_API_KEY')),
      }, options.headers or {}),
      body = vim.tbl_deep_extend('force', params, { stream = true }),
    }, {
      on_message = function(msg)
        local data = util.json.decode(msg.data)

        local chunk = extract(data)

        if chunk ~= nil then
          if chunk.reasoning_content ~= nil then
            handle.reason(chunk.reasoning_content)
          elseif chunk.finish_reason ~= nil then
            handle.finish(nil, chunk.finish_reason)
          elseif chunk.content ~= nil then
            handle.content(chunk.content)
          end
        end
      end,
      on_error = handler.on_error,
      on_other = handler.on_error,
    })
  end,
  strip_asst_messages_of_reasoning = function(body)
    return vim.tbl_deep_extend('force', body, {
      messages = vim.tbl_map(function(msg)
        if msg.role == 'assistant' then
          return vim.tbl_deep_extend('force', msg, {
            content = strip_reasoning(msg.content),
          })
        else
          return msg
        end
      end, body.messages),
    })
  end,
}

return M
