local segment = require('llm.util.segment')

local M = {}

---@alias ContentsBuilder fun(input: string, context: Context): LlmChatContents Converts input and context to request data. Returns a table of results or a function that takes a resolve function taking a table of results.

---@class ChatPrompt
---@field provider Provider The API provider for this prompt
---@field create ContentsBuilder Creates a new chat buffer with given LlmChatContents
---@field run fun(contents: LlmChatContents): { params: table, options?: table } Converts chat contents into completion request params and provider options

---@class LlmChatMessage
---@field role 'user' | 'assistant'
---@field content string

---@class LlmChatContents
---@field system? string
---@field config table
---@field messages LlmChatMessage[]

--- Splits lines into array of { role: 'user' | 'assistant', content: string }
--- If first line starts with '> ', then the rest of that line is system message
---@param text string Text of buffer. '\n======\n' denote alternations between user and assistant roles
---@return { messages: { role: 'user'|'assistant', content: string}[], system?: string }
local function split_messages(text)
  local lines = vim.fn.split(text, '\n')
  local messages = {}

  local system;

  local chunk_lines = {}
  local chunk_is_user = true

  --- Insert message and reset/toggle chunk state. User text is trimmed.
  local function add_message()
    local text_ = table.concat(chunk_lines, '\n')

    table.insert(messages, {
      role = chunk_is_user and 'user' or 'assistant',
      content = chunk_is_user and vim.trim(text_) or text_
    })

    chunk_lines = {}
    chunk_is_user = not chunk_is_user
  end

  for i, line in ipairs(lines) do
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
    add_message()
  end

  return {
    system = system,
    messages = messages
  }
end

---@param text string Input text of buffer
---@return { config?: table, rest: string }
local function parse_config(text)
  local params_text, rest = text:match('^%-%-%-\n(.-)\n%-%-%-\n(.*)$')

  if params_text == nil then
    return { config = {}, rest = text }
  end

  local config = vim.fn.luaeval(params_text)

  if type(config) ~= 'table' then
    error('Evaluated config text is not a lua table')
  end

  return {
    config = config,
    rest = rest
  }
end

--- Parse a chat file. Can begin with a lua table of config between `---`.
--- If the next line starts with `> `, it is parsed as the system instruction.
--- The rest of the text is parsed as alternating user/assistant messages, with
--- `\n======\n` delimiters.
---
--- Example file:
--- ```
--- ---
--- {
---   model = "gpt-3.5-turbo"
--- }
--- ---
--- > You are a helpful assistant
---
--- Count to three
---
--- ======
--- 1, 2, 3.
--- ======
--- ```
---
--- Returns the table:
--- {
---   config = {
---     model = 'gpt-3.5-turbo'
---   },
---   system = 'You are a helpful assistant',
---   messages = {
---     { role = 'user', content = 'Count to three' },
---     { role = 'assistant', content = '1, 2, 3.' }
---   }
--- }
---@param text string
---@return LlmChatContents
function M.parse(text)
  local parsed = parse_config(text)
  local messages_and_system = split_messages(parsed.rest)

  return vim.tbl_extend('force', messages_and_system, { config = parsed.config })
end

---@param contents LlmChatContents
---@return string
function M.to_string(contents)
  local result = ''

  if not vim.tbl_isempty(contents.config) then
    result = result .. '---\n' .. vim.inspect(contents.config) .. '\n---\n'
  end

  if contents.system then
    result = result .. '> ' .. contents.system .. '\n'
  end

  for i,message in ipairs(contents.messages) do
    if i ~= 1 then
      result = result .. '\n======\n'
    end

    if message.role == 'user' then
      result = result .. '\n' .. message.content .. '\n'
    else
      result = result .. message.content
    end
  end

  return vim.fn.trim(result, '\n', 2) -- trim trailing newline
end

---@param chat_prompt ChatPrompt
---@param chat_name string
---@param input_context InputContext
function M.create_new_chat(chat_prompt, chat_name, input_context)
  local chat_contents = chat_prompt.create(
    input_context.input,
    input_context.context
  )

  assert(
    chat_contents.config,
    'Chat prompt ' .. chat_name .. '.create() needs to return a table with a "config" value'
  )

  -- default chat to provided chat_name
  chat_contents.config.chat = chat_contents.config.chat or chat_name

  local new_buffer_text = M.to_string(chat_contents)

  vim.cmd.vnew()
  vim.o.ft = 'llmchat'
  vim.cmd.syntax({'sync', 'fromstart'})

  vim.api.nvim_buf_set_lines(
    0,
    0,
    0,
    false,
    vim.fn.split(new_buffer_text, '\n')
  )
end

---@param opts { chats?: table<string, ChatPrompt> }
function M.run_chat(opts)
  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local contents = M.parse(
    table.concat(buf_lines, '\n')
  )

  local chat_name = assert(
    contents.config.chat,
    'Chat buffer missing chat name in header'
  )

  ---@type ChatPrompt
  local chat_prompt = assert(
    vim.tbl_get(opts, 'chats', chat_name),
    'Chat not found'
  )

  local run_config = chat_prompt.run(contents)
  if run_config == nil then
    error('Chat prompt run() returned nil')
  end

  local seg = segment.create_segment_at(#buf_lines, 0)
  seg.add('======\n')

  local handlers = {
    on_partial = seg.add,
    on_finish = function()
      seg.add('\n======\n')
      seg.clear_hl()
    end,
    on_error = error
  }

  chat_prompt.provider.request_completion(handlers, run_config.params, run_config.options)
end

return M
