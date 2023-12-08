local util = require('model.util')
local curl = require('model.util.curl')
local segment = require('model.util.segment')

local M = {}

local function extract_message_response(candidate)
  return candidate.content
end

local function extract_text_response(candidate)
  return candidate.output
end

local function scroll(text, rate, set)
  local run = true

  local function scroll_(t)
    vim.defer_fn(function ()
      if run then
        local tail = t:sub(#t)
        local head = t:sub(1, #t - 1)
        local text_ = tail .. head

        set('<' .. text_ .. '>')

        return scroll_(text_)
      end
    end, rate)
  end

  scroll_(text)

  return function()
    set('')
    run = false
  end
end

local function show_pending_marquee(handlers)
  if handlers.segment then
    local handler_seg = handlers.segment.details()
    local pending = segment.create_segment_at(
      handler_seg.row + 1,
      handler_seg.col,
      'Comment'
    )
    return scroll('PaLM   ', 160, pending.set_text)
  end

  return function() end
end

---@param handlers StreamHandlers
---@param params? any Additional options for PaLM endpoint
---@param options { model: string, method: string }
function M.request_completion(handlers, params, options)
  options = options or {}

  local model = options.model or 'chat-bison-001'
  local method = options.method or 'generateMessage'
  local extract = extract_message_response

  if model == 'text-bison-001' then
    model = params.model
    method = 'generateText'
    extract = extract_text_response
  end

  local remove_marquee = show_pending_marquee(handlers)

  local function handle_raw(raw_data)
    local response = util.json.decode(raw_data)

    if response == nil then
      error('Failed to decode json response:\n' .. raw_data)
    end

    if response.error ~= nil or not response.candidates then
      handlers.on_error(response)
      remove_marquee()
    else
      local first_candidate = response.candidates[1]

      if first_candidate == nil then
        error('No candidates returned:\n' .. raw_data)
      end

      local result = extract(first_candidate)

      -- TODO change reason to error, return nil for successful completion
      handlers.on_finish(result, 'stop')
      remove_marquee()
    end
  end

  local function handle_error(raw_data)
    handlers.on_error(raw_data)
  end

  return curl.stream({
    headers = {
      ['Content-Type']= 'application/json',
    },
    method = 'POST',
    url =
        'https://generativelanguage.googleapis.com/v1beta2/models/'
        .. model .. ':'
        .. method
        .. '?key=' .. util.env_memo('PALM_API_KEY'),
    body = params
  }, handle_raw, handle_error)
end

function M.adapt(standard_prompt)
  local function palm_message(msg)
    return {
      author = msg.role == 'user' and '0' or '1',
      content = msg.content
    }
  end

  local examples = {}

  local current_example = {}
  for _, example in ipairs(standard_prompt.fewshot) do
    if example.role == 'user' then
      current_example.input = palm_message(example)
    else
      current_example.output = palm_message(example)
    end

    if current_example.input and current_example.output then
      table.insert(examples, current_example)
      current_example = {}
    end
  end

  return {
    prompt = {
      context = standard_prompt.instruction,
      examples = examples,
      messages = vim.tbl_map(
        palm_message,
        standard_prompt.messages
      )
    }
  }
end

M.default_prompt = {
  provider = M,
  builder = function(input)
    return {
      prompt = {
        messages = {
          {
            content = input
          }
        }
      }
    }
  end
}

return M
