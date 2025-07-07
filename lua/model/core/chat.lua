local segment = require('model.util.segment')
local util = require('model.util')
local juice = require('model.util.juice')

local M = {}

---@class ChatPrompt
---@field provider Provider The API provider for this prompt
---@field create fun(input: string, context: Context): string | ChatContents Converts input and context to the first message text or ChatContents
---@field run fun(messages: ChatMessage[], config: ChatConfig): table | fun(resolve: fun(params: table): nil ) ) Converts chat messages and config into completion request params
---@field runOptions? fun(): table Builds additional options to merge into chat prompt options. E.g. for auth tokens that shouldn't be written to the chat config header.
---@field system? string System instruction
---@field params? table Static request parameters
---@field options? table Provider options
---@field completion_prefix? string Prefix assistant message for completion requests

---@class DataSection
---@field label? string
---@field content string

---@class ChatMessage
---@field role 'user' | 'assistant'
---@field content string Content without data sections
---@field data_sections DataSection[]
---@field raw_content string Full content including data section unparsed text

---@alias ChatConfig { system?: string, params?: table, options?: table }

---@class ChatContents
---@field config ChatConfig Configuration for this chat buffer, used by chatprompt.run
---@field messages ChatMessage[] Messages in the chat buffer

--- Splits lines into array of { role: 'user' | 'assistant', content: string }
--- If first line starts with '> ', then the rest of that line is system message
---@param text string[] Text of buffer. '\n======\n' denote alternations between user and assistant roles
---@return { messages: ChatMessage[], system?: string, last_message_has_separator: boolean }
local function split_messages(text)
  local messages = {}

  local system

  local chunk_lines = {}
  local chunk_is_user = true
  local last_message_has_separator = true

  --- Insert message and reset/toggle chunk state. User text is trimmed.
  local function add_message()
    local aggregate_text = table.concat(chunk_lines, '\n')

    ---@type DataSection[]
    local data_sections = {}

    local clean_content = aggregate_text:gsub(
      '\n?<<<<<< (.-)\n(.-)\n>>>>>>\n?',
      function(label, content)
        table.insert(data_sections, {
          label = label,
          content = content,
        })
        return ''
      end
    )

    table.insert(messages, {
      role = chunk_is_user and 'user' or 'assistant',
      content = vim.trim(clean_content),
      data_sections = data_sections,
      raw_content = aggregate_text,
    })

    chunk_lines = {}
    chunk_is_user = not chunk_is_user
  end

  for i, line in ipairs(text) do
    if i == 1 then
      system = line:match('^> (.+)')

      if system == nil then
        table.insert(chunk_lines, line)
      end
    elseif line == '======' then
      add_message()
    else
      table.insert(chunk_lines, line)
    end
  end

  -- add text after last `======` if not empty
  if table.concat(chunk_lines, '') ~= '' then
    last_message_has_separator = false
    add_message()
  end

  return {
    system = system,
    messages = messages,
    last_message_has_separator = last_message_has_separator,
  }
end

---@param text string[] Input text of buffer
---@return { chat: string, config?: table, rest: string[] }
local function parse_config(text)
  if #text < 1 then
    error('Chat buffer empty')
  end

  if text[1]:match('^---$') then
    error('Chat buffer must start with chat name, not config')
  end

  if text[1]:match('^>') then
    error('Chat buffer must start with chat name, not system instruction')
  end

  local chat = text[1]

  if chat == '' then
    error('Chat buffer must start with chat name, not empty line')
  end

  local params = {}
  local i = 2
  if text[2] == '---' then
    i = 3
    while i < #text and text[i] ~= '---' do
      table.insert(params, text[i])
      i = i + 1
    end

    if text[i] == '---' then
      i = i + 1 -- skip the ending '---'
    else
      error('Chat buffer params block incomplete')
    end
  end

  local rest = {}
  while i <= #text do
    table.insert(rest, text[i])
    i = i + 1
  end

  if #params == 0 then
    return {
      config = {},
      rest = rest,
      chat = chat,
    }
  else
    local config = vim.fn.luaeval(table.concat(params, '\n'))

    if type(config) ~= 'table' then
      error('Evaluated config text is not a lua table')
    end

    return {
      config = config,
      rest = rest,
      chat = chat,
    }
  end
end

--- Parse a chat file. Must start with a chat name, can follow with a lua table
--- of config between `---`. If the next line starts with `> `, it is parsed as
--- the system instruction. The rest of the text is parsed as alternating
--- user/assistant messages, with `\n======\n` delimiters.
---@param text string[]
---@return { contents: ChatContents, chat: string, trail: boolean }
function M.parse(text)
  local parsed = parse_config(text)

  local messages_and_system = split_messages(parsed.rest)
  if messages_and_system.system ~= nil then
    parsed.config.system = messages_and_system.system
  end

  return {
    contents = {
      messages = messages_and_system.messages,
      config = vim.tbl_extend('force', parsed.config, {
        system = messages_and_system.system,
      }),
    },
    chat = parsed.chat,
    last_message_has_separator = messages_and_system.last_message_has_separator,
  }
end

---@param contents ChatContents
---@param name string
---@return string
function M.to_string(contents, name)
  local result = name .. '\n'

  if not vim.tbl_isempty(contents.config) then
    -- TODO consider refactoring this so we're not treating system special
    -- Either remove it from contents.config so that it sits next to config
    -- or just let it be a normal config field
    local without_system = util.table.without(contents.config, 'system')

    if without_system and not vim.tbl_isempty(without_system) then
      result = result .. '---\n' .. vim.inspect(without_system) .. '\n---\n'
    end

    if contents.config.system then
      result = result .. '> ' .. contents.config.system .. '\n'
    end
  end

  for i, message in ipairs(contents.messages) do
    if i ~= 1 then
      result = result .. '\n======\n'
    end

    if message.data_sections then
      for _, section in ipairs(message.data_sections) do
        result = result
          .. string.format(
            '<<<<<< %s\n%s\n>>>>>>\n',
            section.label,
            section.content
          )
      end
    end

    if message.role == 'user' then
      result = result .. '\n' .. message.content .. '\n'
    else
      result = result .. message.content
    end
  end

  if #contents.messages % 2 == 0 then
    result = result .. '\n======\n'
  end

  return vim.fn.trim(result, '\n', 2) -- trim trailing newline
end

function M.build_contents(chat_prompt, input_context)
  local first_message_or_contents =
    chat_prompt.create(input_context.input, input_context.context)

  local config = {
    options = chat_prompt.options,
    params = chat_prompt.params,
    system = chat_prompt.system,
  }

  ---@type ChatContents
  local chat_contents

  if type(first_message_or_contents) == 'string' then
    chat_contents = {
      config = config,
      messages = {
        {
          role = 'user',
          content = first_message_or_contents,
        },
      },
    }
  elseif type(first_message_or_contents) == 'table' then
    chat_contents = vim.tbl_deep_extend(
      'force',
      { config = config },
      first_message_or_contents
    )
  else
    error(
      'ChatPrompt.create() needs to return a string for the first message or an ChatContents'
    )
  end

  return chat_contents
end

local function is_buffer_empty_and_unnamed()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local buffer_name = vim.api.nvim_buf_get_name(0)
  return #lines == 1 and lines[1] == '' and buffer_name == ''
end

function M.create_buffer(text, smods)
  if not is_buffer_empty_and_unnamed() then
    -- only create a new buffer if we're not in an empty buffer
    if smods.tab > 0 then
      vim.cmd.tabnew()
    elseif smods.horizontal then
      vim.cmd.new()
    else
      vim.cmd.vnew()
    end
  end

  vim.o.ft = 'mchat'
  vim.cmd.syntax({ 'sync', 'fromstart' })

  local lines = vim.fn.split(text, '\n')
  ---@cast lines string[]

  vim.api.nvim_buf_set_lines(0, 0, 0, false, lines)
end

local function needs_nl(buf_lines)
  local last_line = buf_lines[#buf_lines]

  return not last_line or vim.fn.trim(last_line) ~= ''
end

---@param opts { chats?: table<string, ChatPrompt> }
function M.run_chat(opts)
  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local parsed = M.parse(buf_lines)

  local chat_name =
    assert(parsed.chat, 'Chat buffer first line must be a chat prompt name')

  ---@type ChatPrompt
  local chat_prompt = assert(
    vim.tbl_get(opts, 'chats', chat_name),
    'Chat "' .. chat_name .. '" not found'
  )

  local run_params =
    chat_prompt.run(parsed.contents.messages, parsed.contents.config)

  if run_params == nil then
    error('Chat prompt run() returned nil')
  end

  local starter_separator = needs_nl(buf_lines) and '\n======\n' or '======\n'

  local seg

  local last_msg = parsed.contents.messages[#parsed.contents.messages]

  if last_msg.role == 'user' then
    seg = segment.create_segment_at(#buf_lines, 0)
    if not vim.endswith(vim.trim(table.concat(buf_lines, '\n')), '======') then
      seg.add(starter_separator)
    end
  else
    seg = segment.create_segment_at(#buf_lines - 1, #buf_lines[#buf_lines])
  end

  seg.clear_hl()

  local stop_spinner = juice.spinner(seg, 'Waiting for response.. ')

  local sayer = juice.sayer()

  ---@type StreamHandlers
  local handlers = {
    on_partial = function(text)
      stop_spinner()
      seg.add(text)
      sayer.say(text)
    end,
    on_finish = function(text, reason)
      stop_spinner()
      sayer.finish()

      if text then
        seg.set_text(
          (last_msg.role == 'user' and (starter_separator .. text) or text)
            .. '\n======\n'
        )
      else
        seg.add('\n======\n')
      end

      seg.clear_hl()

      if
        reason
        and reason ~= 'stop'
        and reason ~= 'done'
        and reason ~= 'tool_calls'
      then
        util.notify('Finish reason: ' .. reason)
      end
    end,
    on_error = function(err, label)
      stop_spinner()
      util.notify(vim.inspect(err), vim.log.levels.ERROR, { title = label })
      seg.set_text('')
      seg.clear_hl()
    end,
    on_other = function(x)
      stop_spinner()
      util.show(x)
    end,
    segment = seg,
  }

  local options = parsed.contents.config.options or {}
  local params = parsed.contents.config.params or {}

  if type(chat_prompt.runOptions) == 'function' then
    options = vim.tbl_deep_extend('force', options, chat_prompt.runOptions())
  end

  local function make_request(params_from_run)
    local ok, err = pcall(function()
      seg.data.cancel = chat_prompt.provider.request_completion(
        handlers,
        vim.tbl_deep_extend('force', params, params_from_run),
        options
      )
    end)
    if not ok then
      stop_spinner()
      util.eshow(err)
    end
  end

  if type(run_params) == 'function' then
    run_params(function(async_run_params)
      make_request(async_run_params)
    end)
  else
    make_request(run_params)
  end
end

return M
