local segment = require('model.util.segment')
local util = require('model.util')
local provider = require('model.core.provider')
local scopes = require('model.core.scopes')
local chat = require('model.core.chat')
local input = require('model.core.input')

local M = {}

local function yank_with_line_numbers_and_filename(opts)
  opts = opts or {}
  local register = opts.register or '"'

  -- Get the visual selection range
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  -- Capture the selected lines
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  -- Get current buffer's file name
  local filename = vim.api.nvim_buf_get_name(0)
  filename = filename ~= "" and filename or "[No Name]"

  -- Add the filename and the markdown code fence language syntax
  local file_info = "File: `" .. filename .. "`\n```"

  -- Deduce language from filetype (assuming filename includes proper extension)
  local filetype = vim.bo.filetype

  if filetype and filetype ~= "" then
    file_info = file_info .. filetype .. "\n"
  else
    file_info = file_info .. "\n"
  end

  -- Add line numbers to each line
  for i, line in ipairs(lines) do
    lines[i] = start_line + i - 1 .. ': ' .. line
  end

  -- Join lines into a single string and close the code fence
  local with_numbers = file_info .. table.concat(lines, "\n") .. "\n```"

  -- Set the content in the chosen register
  vim.fn.setreg(register, with_numbers)

  -- Echo a message
  vim.notify('Yanked lines ' .. start_line .. ' to ' .. end_line .. ' with line numbers to register ' .. register)

  -- Return the result as a string
  return with_numbers
end

local function command_request_completion(cmd_params)
  ---Gets the first arg as the prompt name
  ---the rest of the args are passed to the prompt builder as a string
  ---@return Prompt, string
  local function get_prompt_and_args(args)
    local prompt_arg = table.remove(args, 1)

    if not prompt_arg then
      return M.opts.default_prompt, ''
    end

    local prompt = assert(
      scopes.get_prompt(prompt_arg),
      "Prompt '" .. prompt_arg .. "' wasn't found"
    )

    return prompt, table.concat(args, ' ')
  end

  local prompt, args = get_prompt_and_args(cmd_params.fargs or {}) -- seems like fargs can be nil
  local want_visual_selection = cmd_params.range ~= 0

  return provider.request_completion(prompt, args, want_visual_selection)
end

local function command_request_multi_completion_streams(cmd_params)
  local prompt_names = cmd_params.fargs

  local found_prompts = vim.tbl_map(function(name)
    return assert(
      scopes.get_prompt(name),
      "Prompt '" .. name .. "' wasn't found"
    )

  end, prompt_names)
  local want_visual_selection = cmd_params.range ~= 0

  return provider.request_multi_completion_streams(
    found_prompts,
    want_visual_selection
  )
end

local function create_deprecated_command(deprecated_name, new_name, cmd_fn, opts)
  vim.api.nvim_create_user_command(deprecated_name, function(...)
    vim.notify(
      "Command '" .. deprecated_name .. "' is deprecated. Use '" .. new_name .. "' instead.",
      vim.log.levels.WARN
    )
    return cmd_fn(...)
  end, opts)

  vim.api.nvim_create_user_command(new_name, cmd_fn, opts)
end

local function setup_commands()
  local function flash(count, wait, seg, highlight, after)
    vim.defer_fn(function ()
      if count == 0 then after() return end

      if count % 2 == 0 then
        seg.highlight(highlight)
      else
        seg.clear_hl()
      end

      return flash(count - 1, wait, seg, highlight, after)
    end, wait)
  end

  vim.api.nvim_create_user_command(
    'LlmMulti',
    function(...)
      vim.notify(
        'LlmMulti is going to be removed. Open a GH issue to keep it if you use it!',
        vim.log.levels.WARN
      )

      return command_request_multi_completion_streams(...)
    end,
    {
      force = true,
      range = true,
      nargs = '+',
      desc = 'Request multiple prompts at the same time',
      complete = scopes.complete_arglead_prompt_names,
    }
  )

  create_deprecated_command(
    'LlmCancel',
    'Mcancel',
    function()
      local seg = segment.query(util.cursor.position())

      seg.highlight('Special')

      local cancel = seg.data.cancel

      if cancel ~= nil then
        cancel()
      else
        vim.notify('Not cancellable', vim.log.levels.WARN)
      end
    end,
    {
      range = true,
      desc = 'Cancel the completion under the cursor',
      force = true
    }
  )

  create_deprecated_command(
    'LlmDelete',
    'Mdelete',
    function()
      local seg = segment.query(util.cursor.position())
      if seg then
        flash(6, 80, seg, 'DiffDelete', function() seg.delete() end)
      end
    end,
    {
      range = true,
      desc = 'Delete the completion under the cursor, replacing with original text if replacement',
      force = true
    }
  )

  create_deprecated_command(
    'LlmShow',
    'Mshow',
    function()
      local seg = segment.query(util.cursor.position())
      if seg then
        flash(10, 80, seg, 'DiffChange', util.noop)
      end
    end,
    {
      range = true,
      force = true,
      desc = 'Show the completion under the cursor'
    }
  )

  create_deprecated_command(
    'LlmSelect',
    'Mselect',
    function()
      local seg = segment.query(util.cursor.position())

      if seg == nil then return end

      local details = seg.details()

      local start = {
        row = details.row,
        col = details.col
      }

      local stop = {
        row = details.details.end_row,
        col = details.details.end_col
      }

      local visual_select_keys =
        util.cursor.place_with_keys(start)
        .. 'v'
        .. util.cursor.place_with_keys(stop)

      vim.api.nvim_feedkeys(visual_select_keys, 'n', true)
    end,
    {
      force = true,
      desc = 'Select the completion under the cursor'
    }
  )

  create_deprecated_command(
    'Llm',
    'M',
    command_request_completion,
    {
      range = true,
      desc = 'Request completion of selection',
      force = true,
      nargs='*',
      complete = scopes.complete_arglead_prompt_names,
    }
  )

  vim.api.nvim_create_user_command(
    'Model',
    command_request_completion,
    {
      range = true,
      desc = 'Request completion of selection',
      force = true,
      nargs='*',
      complete = scopes.complete_arglead_prompt_names,
    }
  )

  local store = require('model.store')

  local handle_store_command = {
    query = function(args)
      local query_prompt = args.args:sub(7)
      -- TODO figure out sane defaults for count and similarity threshold
      local results = store.query_store(query_prompt, 5, 0.5)
      vim.notify(vim.inspect(results))
    end,
    init = function()
      store.init()
    end
  }

  create_deprecated_command(
    'LlmStore',
    'Mstore',
    function(a)
      -- local args = a.fargs
      local command = a.fargs[1]

      local handler = handle_store_command[command]
      if handler == nil then
        error('Unknown Mstore command ' .. command)
      else
        return handler(a)
      end
    end,
    {
      desc = 'Mstore',
      force = true,
      nargs='+',
      complete = function(arglead)
        return vim.fn.matchfuzzy(vim.tbl_keys(handle_store_command), arglead)
      end
    }
  )

  vim.api.nvim_create_user_command(
    'Mchat',
    function(cmd_params)
      local chat_name = table.remove(cmd_params.fargs, 1)
      local args = table.concat(cmd_params.fargs, ' ')

      if chat_name ~= nil and chat_name ~= '' then -- `:Mchat [name]`

        local chat_prompt = assert(
          vim.tbl_get(M.opts, 'chats', chat_name),
          'Chat prompt "' .. chat_name .. '" not found in setup({chats = {..}})'
        )

        local input_context =
          input.get_input_context(
            input.get_source(cmd_params.range ~= 0), -- want_visual_selection
            args
          )

        if vim.o.ft == 'mchat' then
          -- copy current messages to a new built buffer with target settings

          local current = chat.parse(
            table.concat(
              vim.api.nvim_buf_get_lines(0, 0, -1, false),
              '\n'
            )
          )

          local target = chat.build_contents(chat_prompt, input_context)

          if args == '-' then -- if args is `-`, use the current system instruction
            target.config.system = current.contents.config.system
          elseif args ~= '' then -- if args is not empty, use that as system instruction
            target.config.system = args
          end

          chat.create_buffer(
            chat.to_string(
              {
                config = target.config,
                messages = current.contents.messages,
              },
              chat_name
            )
          )
        else
          local chat_contents = chat.build_contents(chat_prompt, input_context)

          if args ~= '' then
            chat_contents.config.system = args
          end

          chat.create_buffer(chat.to_string(chat_contents, chat_name), chat_name)
        end

      else -- `:Mchat`

        if vim.o.ft ~= 'mchat' then
          error('Not in mchat buffer. Either `:set ft=mchat` or run `:Mchat [name]`.')
        end

        chat.run_chat(M.opts)

      end
    end,
    {
      desc = 'Mchat',
      force = true,
      range = true,
      nargs = '*',
      complete = function(arglead)
        local chats = M.opts.chats
        if chats == nil then return end

        local chat_names = vim.tbl_keys(chats)

        if #arglead == 0 then return chat_names end

        return vim.fn.matchfuzzy(chat_names, arglead)
      end
    })

  vim.api.nvim_create_user_command(
    'Mcount',
    function()
      local count = require('model.store.util').tiktoken_count
      local text = table.concat(
        vim.api.nvim_buf_get_lines(0, 0, -1, false),
        '\n'
      )

      if vim.o.ft == 'mchat' then
        local parsed = chat.parse(text)
        local total = count(vim.json.encode(parsed.contents.messages))

        if parsed.contents.config.system then
          total = total + count(parsed.contents.config.system)
        end

        util.show(total)
      else
        util.show(count(text))
      end
    end,
    {}
  )

  vim.api.nvim_create_user_command(
    'Myank',
    function(cmd_params)
      yank_with_line_numbers_and_filename({ register = cmd_params.args })
    end,
    {
      range = true,
      nargs = '?',
    }
  )
end

---@class SetupOptions
---@field default_prompt? Prompt default = openai. The default prompt (`:M` or `:Model` with no argument)
---@field prompts? table<string, Prompt> default = starters. Add prompts (`:M [name]`)
---@field chats? table<string, ChatPrompt> default = prompts/chats. Add chat prompts (`:MChat [name]`)
---@field hl_group? string default = 'Comment'. Set the default highlight group of in-progress responses
---@field join_undo? boolean default = true. Join streaming response text as a single `u` undo. Edits during streaming will also be undone.

---@param opts? SetupOptions
function M.setup(opts)
  M.opts = vim.tbl_extend('force', {
    default_prompt = require('model.providers.openai').default_prompt,
    prompts = require('model.prompts.starters'),
    chats = require('model.prompts.chats')
  }, opts or {})

  if M.opts.prompts then
    scopes.set_global_user_prompts(M.opts.prompts)
  end

  if M.opts.join_undo == false then
    segment.join_undo = false
  end

  if M.opts.hl_group then
    segment.default_hl = M.opts.hl_group
  end

  setup_commands()

  vim.g.did_setup_model = true
end

M.mode = provider.mode -- convenience export

return M

