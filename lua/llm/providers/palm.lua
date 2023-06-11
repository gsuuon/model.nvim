local curl = require('llm.curl')
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
function M.request_completion_stream(handlers, params)
  local model = 'chat-bison-001'
  local method = 'generateMessage'
  local extract = extract_message_response

  if params.model == 'text-bison-001' then
    model = params.model
    method = 'generateText'
    extract = extract_text_response
    params.model = nil
  end

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

return M
