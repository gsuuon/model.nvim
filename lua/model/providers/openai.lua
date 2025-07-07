local model = require('model')
local util = require('model.util')
local sse = require('model.util.sse')
local tools_handler = require('model.tools.handler')
local juice = require('model.util.juice')
local format = require('model.format.openai')

local M = {}

local default_params = {
  model = 'gpt-4o-mini',
  stream = true,
}

M.default_prompt = {
  provider = M,
  builder = function(input)
    return {
      messages = {
        {
          role = 'user',
          content = input,
        },
      },
    }
  end,
}

local function extract_chat_data(item)
  local data = util.json.decode(item)

  if data ~= nil and data.choices ~= nil then
    return {
      content = (data.choices[1].delta or {}).content,
      finish_reason = data.choices[1].finish_reason,
      tool_calls = (data.choices[1].delta or {}).tool_calls,
    }
  end
end

---@deprecated Completion endpoints are pretty outdated
local function extract_completion_data(item)
  local data = util.json.decode(item)
  if data ~= nil and data.choices ~= nil then
    return {
      content = (data.choices[1] or {}).text,
      finish_reason = data.choices[1].finish_reason,
    }
  end
end

---@param handlers StreamHandlers
---@param params? any Additional options for OpenAI endpoint
---@param options? { url?: string, endpoint?: string, authorization?: string, tools?: string[] | boolean, debug?: boolean } Request endpoint and url. Defaults to 'https://api.openai.com/v1/' and 'chat/completions'. `authorization` overrides the request auth header. If url is provided the environment key will not be sent, you'll need to provide an authorization.
function M.request_completion(handlers, params, options)
  options = options or {}

  local headers = { ['Content-Type'] = 'application/json' }
  if options.authorization then
    headers.Authorization = options.authorization
  elseif not options.url then -- only check the OpenAI env key if options.url wasn't set
    headers.Authorization = 'Bearer ' .. util.env('OPENAI_API_KEY')
  end

  local endpoint = options.endpoint or 'chat/completions' -- TODO does this make compat harder?
  local extract_data = endpoint == 'chat/completions' and extract_chat_data
    or extract_completion_data

  local completion = ''

  local stop_marquee = util.noop
  local waiting_first_response = true

  local tool_handler = tools_handler.tool(model.opts.tools, options.tools)
  local tool_chunk_handler =
    tools_handler.chunk(handlers.on_partial, tool_handler.get_equipped_tools())

  if options.tools then
    local tool_uses = tool_handler.get_uses(params)

    if next(tool_uses) ~= nil then
      return tool_handler.run(tool_uses, handlers.on_finish)
    end

    params.tools =
      format.build_tool_definitions(tool_handler.get_equipped_tools())
  end

  return sse.curl_client({
    headers = headers,
    method = 'POST',
    url = util.path.join(options.url or 'https://api.openai.com/v1/', endpoint),
    body = util.tap_if(
      vim.tbl_deep_extend('force', default_params, params, {
        messages = format.transform_messages(params.messages),
      }),
      options.debug
    ),
  }, {
    on_message = function(message, pending)
      local data = extract_data(message.data)
      stop_marquee()

      if data == nil then
        if not message.data == '[DONE]' then
          handlers.on_error(
            vim.inspect({
              data = message.data,
              pending = pending,
            }),
            'Unrecognized SSE message data'
          )
        end
      else
        if data.content ~= nil then
          completion = completion .. data.content
          handlers.on_partial(data.content)
        elseif data.tool_calls ~= nil then
          for _, tool_call_partial in ipairs(data.tool_calls) do
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
        elseif data.finish_reason ~= nil then
          tool_chunk_handler.finish()
          handlers.on_finish(nil, data.finish_reason)
        elseif waiting_first_response then
          waiting_first_response = false
          handlers.on_partial('') -- stop spinner, we have a response
          stop_marquee = juice.spinner(handlers.segment, 'Thinking...')
        end
      end
    end,
    on_other = function(content)
      stop_marquee()
      -- Non-SSE message likely means there was an error
      handlers.on_error(content, 'OpenAI API error')
    end,
    on_error = function(err)
      stop_marquee()
      handlers.on_error(err)
    end,
  })
end

---@param standard_prompt StandardPrompt
function M.adapt(standard_prompt)
  return {
    messages = util.table.flatten({
      {
        role = 'system',
        content = standard_prompt.instruction,
      },
      standard_prompt.fewshot,
      standard_prompt.messages,
    }),
  }
end

--- Sets default openai provider params. Currently enforces `stream = true`.
function M.initialize(opts)
  default_params = vim.tbl_deep_extend('force', default_params, opts or {}, {
    stream = true, -- force streaming since data parsing will break otherwise
  })
end

-- These are convenience exports for building prompt params specific to this provider
M.prompt = {}

function M.prompt.input_as_message(input)
  return {
    role = 'user',
    content = input,
  }
end

function M.prompt.add_args_as_last_message(messages, context)
  if #context.args > 0 then
    table.insert(messages, {
      role = 'user',
      content = context.args,
    })
  end

  return messages
end

function M.prompt.input_and_args_as_messages(input, context)
  return {
    messages = M.add_args_as_last_message(M.input_as_message(input), context),
  }
end

function M.prompt.with_system_message(text)
  return function(input, context)
    local body = M.input_and_args_as_messages(input, context)

    table.insert(body.messages, 1, {
      role = 'system',
      content = text,
    })

    return body
  end
end

return M
