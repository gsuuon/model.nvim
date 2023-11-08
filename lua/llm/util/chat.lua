local M = {}

---@alias ContentsBuilder fun(input: string, context: Context): LlmChatContents | fun(resolve: fun(results: LlmChatContents)) Converts input and context to request data. Returns a table of results or a function that takes a resolve function taking a table of results.

---@class ChatPrompt
---@field provider Provider The API provider for this prompt
---@field create ContentsBuilder Creates a new chat buffer with given LlmChatContents
---@field run fun(contents: LlmChatContents): table Converts chat contents into request parameters

---@class LlmChatMessage
---@field role 'user' | 'assistant'
---@field content string

---@class LlmChatContents
---@field system? string
---@field params table
---@field messages LlmChatMessage[]

--- Splits lines into array of { role: 'user' | 'assistant', content: string }
--- If first line starts with '> ', then the rest of that line is system message
---@param input string Text of input buffer. '\n======\n' denote alternations between user and assistant roles
---@return { messages: { role: 'user'|'assistant', content: string}[], system?: string }
local function split_messages(input)
  local lines = vim.fn.split(input, '\n')
  local messages = {}

  local system;

  local chunk_lines = {}
  local chunk_is_user = true

  --- Insert message and reset/toggle chunk state. User text is trimmed.
  local function add_message()
    local text = table.concat(chunk_lines, '\n')

    table.insert(messages, {
      role = chunk_is_user and 'user' or 'assistant',
      content = chunk_is_user and vim.trim(text) or text
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

---@param input string Input text of buffer
---@return { params?: table, rest: string }
local function parse_params(input)
  local params_text, rest = input:match('^%-%-%-\n(.-)\n%-%-%-\n(.*)$')

  if params_text == nil then
    return { params = {}, rest = input }
  end

  local params = vim.fn.luaeval(params_text)

  if type(params) ~= 'table' then
    error('Evaluated params text is not a lua table')
  end

  return {
    params = params,
    rest = rest
  }
end

--- Parse a chat file. Can begin with a lua table of params between `---`.
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
---   params = {
---     model = 'gpt-3.5-turbo'
---   },
---   system = 'You are a helpful assistant',
---   messages = {
---     { role = 'user', content = 'Count to three' },
---     { role = 'assistant', content = '1, 2, 3.' }
---   }
--- }
---@return LlmChatContents
function M.parse(input)
  local parsed = parse_params(input)
  local messages_and_system = split_messages(parsed.rest)

  return vim.tbl_extend('force', messages_and_system, { params = parsed.params })
end

---@param contents LlmChatContents
---@return string
function M.to_string(contents)
  local result = ''

  if not vim.tbl_isempty(contents.params) then
    result = result .. '---\n' .. vim.inspect(contents.params) .. '\n---\n'
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

  return result
end

return M
