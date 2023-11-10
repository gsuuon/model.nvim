local curl = require('llm.util.curl')
local util = require('llm.util')

local M = {}

local function extract_message_response(candidate)
  return candidate.content
end

local function extract_text_response(candidate)
  return candidate.output
end

---@param handlers StreamHandlers
---@param params? any Additional options for PaLM endpoint
---@param options { model: string, method: string }
function M.request_completion(handlers, params, _options)
  local options = _options or {}

  local model = options.model or 'chat-bison-001'
  local method = options.method or 'generateMessage'
  local extract = extract_message_response

  if model == 'text-bison-001' then
    model = params.model
    method = 'generateText'
    extract = extract_text_response
  end

  handlers.on_partial('<- palm ->') -- on_finish should ovewrite all partials

  local function handle_raw(raw_data)
    local response = util.json.decode(raw_data)

    if response == nil then
      error('Failed to decode json response:\n' .. raw_data)
    end

    if response.error ~= nil or not response.candidates then
      handlers.on_error(response)
    else
      local first_candidate = response.candidates[1]

      if first_candidate == nil then
        error('No candidates returned:\n' .. raw_data)
      end

      local result = extract(first_candidate)

      -- TODO change reason to error, return nil for successful completion
      handlers.on_finish(result, 'stop')
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
