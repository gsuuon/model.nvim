local curl = require('model.util.curl')
local util = require('model.util')
local provider_util = require('model.providers.util')

local M = {}

local default_params = {
  model = 'gpt-3.5-turbo',
  stream = true
}

M.default_prompt = {
  provider = M,
  builder = function(input)
    return {
      messages = {
        {
          role = 'user',
          content = input
        }
      }
    }
  end
}

local function extract_chat_data(item)
  local data = util.json.decode(item)

  if data ~= nil and data.choices ~= nil then
    return {
      content = (data.choices[1].delta or {}).content,
      finish_reason = data.choices[1].finish_reason
    }
  end
end

---@deprecated Completion endpoints are pretty outdated
local function extract_completion_data(item)
  local data = util.json.decode(item)
  if data ~= nil and data.choices ~= nil then
    return {
      content = (data.choices[1] or {}).text,
      finish_reason = data.choices[1].finish_reason
    }
  end
end

---@param handlers StreamHandlers
---@param params? any Additional options for OpenAI endpoint
---@param options? { url?: string, endpoint?: string, authorization?: string } Request endpoint and url. Defaults to 'https://api.openai.com/v1/' and 'chat/completions'. `authorization` overrides the request auth header. If url is provided the environment key will not be sent, you'll need to provide an authorization.
function M.request_completion(handlers, params, options)
  options = options or {}

  local headers = { ['Content-Type'] = 'application/json' }
  if options.authorization then
    headers.Authorization = options.authorization
  elseif not options.url then -- only check the OpenAI env key if options.url wasn't set
    headers.Authorization = 'Bearer ' .. util.env_memo('OPENAI_API_KEY')
  end

  local endpoint = options.endpoint or 'chat/completions' -- TODO does this make compat harder?
  local extract_data = endpoint == 'chat/completions' and extract_chat_data or extract_completion_data

  local completion = ''

  local sse = provider_util.sse_client({
    on_message = function(message, pending)
      local data = extract_data(message.data)

      if data ~= nil then
        if data.content ~= nil then
          completion = completion .. data.content
          handlers.on_partial(data.content)
        end

        if data.finish_reason ~= nil then
          handlers.on_finish(completion, data.finish_reason)
        end
      elseif not message.data:match('%[DONE%]') then
        handlers.on_error(vim.inspect({
          data = message.data,
          pending = pending
        }), 'Unrecognized SSE message data')
      end
    end,
    on_other = function(content)
      -- Non-SSE message likely means there was an error
      handlers.on_error(content, 'OpenAI API error')
    end,
    on_error = handlers.on_error
  })

  return curl.stream(
    {
      headers = headers,
      method = 'POST',
      url = util.string.joinpath(
        options.url or 'https://api.openai.com/v1/',
        endpoint
      ),
      body = vim.tbl_deep_extend(
        'force',
        default_params,
        params
      ),
    },
    sse.on_stdout,
    sse.on_error,
    sse.on_exit
  )
end

---@param standard_prompt StandardPrompt
function M.adapt(standard_prompt)
  return {
    messages = util.table.flatten({
      {
        role = 'system',
        content = standard_prompt.instruction
      },
      standard_prompt.fewshot,
      standard_prompt.messages
    }),
  }
end

--- Sets default openai provider params. Currently enforces `stream = true`.
function M.initialize(opts)
  default_params = vim.tbl_deep_extend('force',
    default_params,
    opts or {},
    {
      stream = true -- force streaming since data parsing will break otherwise
    })
end

-- These are convenience exports for building prompt params specific to this provider
M.prompt = {}

function M.prompt.input_as_message(input)
  return {
    role = 'user',
    content = input
  }
end

function M.prompt.add_args_as_last_message(messages, context)
  if #context.args > 0 then
    table.insert(messages, {
      role = 'user',
      content = context.args
    })
  end

  return messages
end

function M.prompt.input_and_args_as_messages(input, context)
  return {
    messages =
      M.add_args_as_last_message(
        M.input_as_message(input),
        context
      )
  }
end

function M.prompt.with_system_message(text)
  return function(input, context)
    local body = M.input_and_args_as_messages(input, context)

    table.insert(body.messages, 1, {
      role = 'system',
      content = text
    })

    return body
  end
end

return M
