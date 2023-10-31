local M = {}

--- Splits lines into array of { role: 'user' | 'assistant', content: string }
--- If first line starts with '> ', then the rest of that line is system message
---@param input string Text of input buffer. '\n======\n' denote alternations between user and assistant roles
---@return { role: 'user'|'assistant'|'system', content: string}[] messages
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

  add_message()

  if system ~= nil then
    table.insert(messages, 1, {
      role = 'system',
      content = system
    })
  end

  return messages
end


---@param input string Input text of buffer
---@return { params: table, rest: string }
local function parse_yaml_params(input)
  local params_text, rest = input:match('^%-%-%-\n(.-)\n%-%-%-\n(.+)$')

  if params_text == nil then
    return { params = {}, rest = input }
  end

  local params_lines = vim.fn.split(params_text, '\n')
  ---@cast params_lines string[]

  local params = {}

  for _,line in ipairs(params_lines) do
    local label, value = line:match('(.-): (.+)')
    if label ~= '' then
      params[label] = value
    end
  end

  return {
    params = params,
    rest = rest
  }
end

---Parse input text. Frontmatter yaml style (1 deep), system message with > in next line, and alternating 'user', 'assistant' messages. Example:
--- ```
--- ---
--- model: gpt-3.5-turbo
--- ---
--- > You are a helpful assistant
---
--- Count to three
---
--- ===
--- 1, 2, 3.
--- ===
--- ```
--- Returns the table:
--- {
---   model = 'gpt-3.5-turbo'
---   messages = {
---     { role = 'system', content = 'You are a helpful assistant' },
---     { role = 'user', content = 'Count to three' },
---     { role = 'assistant', content = '1, 2, 3.' }
---   }
--- }
---@return { messages: { role: 'user'|'assistant'|'system', content: string}[] } | table
function M.parse(input)
  local parsed = parse_yaml_params(input)
  local messages = split_messages(parsed.rest)

  return vim.tbl_extend('force', parsed.params, { messages = messages })
end

return M
