local segment = require('model.util.segment')
local util = require('model.util')
local juice = require('model.util.juice')

local M = {}

---@class ChatCompletionOptions Options for Chat Completion mode
---@field prefix? string Prefix assistant message for completion requests (like an opening codefence)
---@field suffix? string Suffix to add to completion responses (like a trailing codefence)
---@field run? fun(messages: ChatMessage[], config: ChatConfig): table | fun(resolve: fun(params: table): nil ) ) Override ChatPrompt run
---@field create? fun(input: string, context: Context): string | ChatContents Override chatprompt create
---@field system? string Override system instruction
---@field params? table Override static request parameters
---@field options? table Override provider options

---@class ChatPrompt
---@field provider Provider The API provider for this prompt
---@field create fun(input: string, context: Context): string | ChatContents Converts input and context to the first message text or ChatContents
---@field run fun(messages: ChatMessage[], config: ChatConfig): table | fun(resolve: fun(params: table): nil ) ) Converts chat messages and config into completion request params
---@field runOptions? fun(): table Builds additional options to merge into chat prompt options. E.g. for auth tokens that shouldn't be written to the chat config header.
---@field system? string System instruction
---@field params? table Static request parameters
---@field options? table Provider options
---@field completion? ChatCompletionOptions

---@class DataSection
---@field label? string
---@field content string

---@class ChatMessage
---@field role 'user' | 'assistant'
---@field content string Content without data sections
---@field data_sections? DataSection[]
---@field raw_content? string Full content including data section unparsed text

---@alias ChatConfig { system?: string, params?: table, options?: table }

---@class ChatContents
---@field config ChatConfig Configuration for this chat buffer, used by chatprompt.run
---@field messages ChatMessage[] Messages in the chat buffer

---@class Chat
---@field contents ChatContents
---@field chat string name of the chat handler
---@field trail? boolean last message has a trailing separator

local function emit_event(name, data)
  vim.api.nvim_exec_autocmds('User', {
    pattern = name,
    data = data,
  })
end

local function parse_data_sections(content)
  local data_sections = {}
  local lines = type(content) == 'string' and vim.split(content, '\n')
    or content
  local current_section = nil
  local current_label = nil
  local current_content = {}
  local regular_content = {}

  for _, line in ipairs(lines) do
    if current_section then
      if line:match('^>>>>>>$') then
        table.insert(data_sections, {
          label = current_label,
          content = table.concat(current_content, '\n'),
        })
        current_section = nil
        current_label = nil
        current_content = {}
      else
        table.insert(current_content, line)
      end
    else
      local label = line:match('^<<<<<< (.+)$')
      if label then
        current_section = true
        current_label = label
      else
        -- Regular content line
        table.insert(regular_content, line)
      end
    end
  end

  -- Handle case where we have leftover content in current_section (unclosed section)
  if current_section then
    table.insert(data_sections, {
      label = current_label,
      content = table.concat(current_content, '\n'),
    })
  end

  return {
    data_sections = data_sections,
    content = vim.trim(table.concat(regular_content, '\n')),
  }
end

--- Splits lines into array of { role: 'user' | 'assistant', content: string }
--- If first line starts with '> ', then the rest of that line is system message
---@param text string[] Text of buffer. '\n======\n' denote alternations between user and assistant roles
---@return { messages: ChatMessage[], system?: string, last_message_has_separator: boolean }
local function split_messages(text)
  local system_from_header

  local chunk_lines = {}
  local chunk_is_user = true
  local last_message_has_separator = true
  local messages = {}

  --- Insert message and reset/toggle chunk state. User text is trimmed.
  local function add_message()
    local aggregate_text = table.concat(chunk_lines, '\n')

    local parsed_message = parse_data_sections(aggregate_text)

    table.insert(messages, {
      role = chunk_is_user and 'user' or 'assistant',
      content = parsed_message.content,
      data_sections = parsed_message.data_sections,
      raw_content = aggregate_text,
    })

    chunk_lines = {}
    chunk_is_user = not chunk_is_user
  end

  for i, line in ipairs(text) do
    if i == 1 then
      system_from_header = line:match('^> (.+)')

      if system_from_header == nil then
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

  -- Look for system data section in first message
  local system_from_data
  if #messages > 0 then
    local first_msg = messages[1]
    if first_msg.data_sections then
      for _, section in ipairs(first_msg.data_sections) do
        if section.label == 'system' then
          system_from_data = section.content
          break
        end
      end
    end
  end

  -- Combine system messages if both exist
  local system
  if system_from_header and system_from_data then
    system = system_from_header .. '\n' .. system_from_data
  else
    system = system_from_header or system_from_data
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
---@return Chat
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
    trail = messages_and_system.last_message_has_separator,
  }
end

---@param contents ChatContents
---@param name string
---@return string
function M.to_string(contents, name)
  local result_lines = { name }

  if not vim.tbl_isempty(contents.config) then
    -- TODO consider refactoring this so we're not treating system special
    -- Either remove it from contents.config so that it sits next to config
    -- or just let it be a normal config field
    local without_system = util.table.without(contents.config, 'system')

    if without_system and not vim.tbl_isempty(without_system) then
      table.insert(result_lines, '---')
      vim.list_extend(
        result_lines,
        vim.split(vim.inspect(without_system), '\n')
      )
      table.insert(result_lines, '---')
    end

    if contents.config.system then
      table.insert(result_lines, '> ' .. contents.config.system)
    end
  end

  for i, message in ipairs(contents.messages) do
    if i ~= 1 then
      table.insert(result_lines, '======')
    end

    if message.data_sections then
      for _, section in ipairs(message.data_sections) do
        table.insert(result_lines, '<<<<<< ' .. section.label)
        vim.list_extend(
          result_lines,
          vim.split(section.content, '\n', { trimempty = true })
        )
        table.insert(result_lines, '>>>>>>')
      end
    end

    vim.list_extend(
      result_lines,
      vim.split(message.content, '\n', { trimempty = true })
    )
  end

  if #contents.messages % 2 == 0 then
    table.insert(result_lines, '======')
  end

  return table.concat(result_lines, '\n')
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
  smods = smods or { tab = 0 }

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

  vim.api.nvim_buf_set_lines(0, 0, 0, false, lines)
end

---@param chat Chat
---@param handlers StreamHandlers
---@param chat_prompt ChatPrompt
local function create_chat_runner(chat, handlers, chat_prompt)
  local run_params =
    chat_prompt.run(chat.contents.messages, chat.contents.config)

  if run_params == nil then
    error('Chat prompt run() returned nil')
  end

  local options = chat.contents.config.options or {}
  local params = chat.contents.config.params or {}

  if type(chat_prompt.runOptions) == 'function' then
    options = vim.tbl_deep_extend('force', options, chat_prompt.runOptions())
  end

  ---@param on_run fun(cancel: fun())
  return function(on_run)
    if type(run_params) == 'function' then
      run_params(function(async_run_params)
        on_run(
          chat_prompt.provider.request_completion(
            handlers,
            vim.tbl_deep_extend('force', params, async_run_params),
            options
          )
        )
      end)
    else
      on_run(
        chat_prompt.provider.request_completion(
          handlers,
          vim.tbl_deep_extend('force', params, run_params),
          options
        )
      )
    end
  end
end

---@param opts { chats: table<string, ChatPrompt> }
function M.run_chat(opts)
  local bufnr = vim.fn.bufnr()

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  local chat = M.parse(lines)
  local chat_prompt = assert(
    vim.tbl_get(opts, 'chats', chat.chat),
    'Chat prompt "' .. chat.chat .. '" not found in setup({chats = {..}})'
  )

  local create_line = #lines

  while lines[create_line] == '' do
    create_line = create_line - 1
  end

  local seg = segment.create_segment_at(create_line, 0)

  if not chat.trail then
    seg.add_line('======')
  end

  local stop_spinner = juice.spinner({
    position = util.position.row_below(seg.get_span().stop),
    label = 'Waiting for response.. ',
    bufnr = bufnr,
  })

  local sayer = juice.sayer()

  ---@type StreamHandlers
  local handlers = {
    on_partial = function(text)
      stop_spinner()
      sayer.say(text)

      -- Check if text matches exactly a data delimiter pattern with newlines
      local is_delimiter = text:match('^\n<<<<<<.-\n$')
        or text:match('^\n>>>>>>\n$')

      if is_delimiter then
        seg.add_line(vim.trim(text))
      else
        seg.add(text)
      end

      vim.schedule(function()
        emit_event('ModelChatPartial', {
          text = text,
          bufnr = bufnr,
        })
      end)
    end,
    on_finish = function(text, reason)
      stop_spinner()
      sayer.finish()

      util.buf.reset_mchat_folds(bufnr)

      if text then
        if chat.trail then
          seg.set_text(text)
        else
          seg.set_text('')
          seg.add_line('======')
          seg.add(text)
        end
      else
        seg.add_line('======')
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

      -- The streaming can mess up parsing especially with injections - try a full reparse.
      local parser = vim.treesitter.get_parser(bufnr)
      if parser then
        parser:parse()
      end

      vim.schedule(function()
        emit_event('ModelChatFinished', {
          chat = M.parse(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)),
          bufnr = bufnr,
        })
      end)
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

  local chat_runner = create_chat_runner(chat, handlers, chat_prompt)

  local ok, err = pcall(chat_runner, function(cancel)
    seg.data.cancel = cancel
  end)

  if not ok then
    stop_spinner()
    util.eshow(err)
  end
end

local function insert_or_replace_segment(source)
  if source.selection ~= nil then
    util.buf.set_text(source.selection, {})

    local seg = segment.create_segment_at(
      source.selection.start.row,
      source.selection.start.col,
      nil,
      0
    )

    seg.data.original = source.lines

    return seg
  else
    local pos = util.cursor.position()

    local seg = segment.create_segment_at(pos.row, pos.col, nil, 0)

    seg.data.original = {}

    return seg
  end
end

---@param chat Chat
---@param chat_prompt ChatPrompt
---@param seg Segment
local function run_chat_completion(chat, chat_prompt, seg)
  seg.data.chat = chat

  local stop_spinner = juice.spinner({
    position = seg.get_span().stop,
    label = 'Waiting for response ..',
  })

  local response = ''

  ---@type StreamHandlers
  local handlers = {
    on_error = function(err)
      stop_spinner()
      util.eshow(err)
    end,
    on_finish = function()
      stop_spinner()
      seg.clear_hl()

      if chat_prompt.completion and chat_prompt.completion.prefix then
        -- Replace the prefix message
        response = chat_prompt.completion.prefix
          .. response
          .. (chat_prompt.completion.suffix or '')

        local parsed = parse_data_sections(response)

        seg.data.chat.contents.messages[#seg.data.chat.contents.messages] = {
          role = 'assistant',
          raw_content = response,
          content = parsed.content,
          data_sections = parsed.data_sections,
        }
      else
        local parsed = parse_data_sections(response)
        table.insert(seg.data.chat.contents.messages, {
          role = 'assistant',
          raw_content = response,
          content = parsed.content,
          data_sections = parsed.data_sections,
        })
      end

      local span = seg.get_span()
      local seg_height = span.stop.row - span.start.row + 1

      seg.set_virt(
        string.format(
          '%s | %d %s',
          chat.chat,
          seg_height,
          seg_height > 1 and 'lines' or 'line'
        ),
        'Comment',
        {
          virt_text_pos = 'right_align',
          sign_text = '⢸',
          sign_hl_group = 'modelChatCompletionSign',
        },
        util.eshow
      )
    end,
    on_partial = function(partial)
      stop_spinner()
      seg.add(partial)
      response = response .. partial
    end,
    on_other = function(other)
      stop_spinner()
      util.show(other)
    end,
    segment = seg,
  }

  local chat_runner = create_chat_runner(chat, handlers, chat_prompt)

  local ok, err = pcall(chat_runner, function(cancel)
    seg.data.cancel = cancel
  end)

  if not ok then
    stop_spinner()
    util.eshow(err)
  end
end

---@param chat_prompt ChatPrompt
local function override_with_completion_config(chat_prompt)
  local completion = chat_prompt.completion or {}
  return vim.tbl_deep_extend('force', chat_prompt, {
    create = completion.create,
    run = completion.run,
    params = completion.params,
    options = completion.options,
    system = completion.system,
  })
end

---@param input_context InputContext
---@param chat_prompt ChatPrompt
---@param source Source
function M.start_chat_completion(chat_name, chat_prompt, input_context, source)
  local seg = insert_or_replace_segment(source)

  chat_prompt = override_with_completion_config(chat_prompt)

  ---@type Chat
  local chat = {
    contents = M.build_contents(chat_prompt, input_context),
    chat = chat_name,
  }

  if chat_prompt.completion and chat_prompt.completion.prefix then
    table.insert(chat.contents.messages, {
      role = 'assistant',
      content = chat_prompt.completion.prefix,
    })
  end

  run_chat_completion(chat, chat_prompt, seg)
end

function M.continue_chat_completion(opts, instruction)
  local segments = segment.query_all(util.cursor.position())

  local found_segment
  do
    for _, seg in ipairs(segments) do
      if seg.data.chat.contents then
        found_segment = seg
        break
      end
    end
  end

  if found_segment then
    ---@type Chat
    local chat = found_segment.data.chat
    local chat_prompt = opts.chats[chat.chat]

    if not chat_prompt then
      error('Chat handler not found for ' .. chat.chat)
    end

    found_segment.set_text('')

    table.insert(chat.contents.messages, {
      role = 'user',
      content = instruction,
    })

    chat_prompt = override_with_completion_config(chat_prompt)

    if chat_prompt.completion and chat_prompt.completion.prefix then
      table.insert(chat.contents.messages, {
        role = 'assistant',
        content = chat_prompt.completion.prefix,
      })
    end

    run_chat_completion(chat, chat_prompt, found_segment)
  else
    util.eshow('Nothing to continue here')
  end
end

function M.parse_buffer_to_json(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return vim.json.encode(M.parse(lines))
end

return M
