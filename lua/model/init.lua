local util = require('model.util')
local files = require('model.util.files')
local segment = require('model.util.segment')
local juice = require('model.util.juice')
local provider = require('model.core.provider')
local scopes = require('model.core.scopes')
local chat = require('model.core.chat')
local input = require('model.core.input')

local M = {}

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

---@diagnostic disable-next-line: unused-function, unused-local
local function _command_request_multi_completion_streams(cmd_params)
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

---@diagnostic disable-next-line: unused-function, unused-local
local function _create_deprecated_command(
  deprecated_name,
  new_name,
  cmd_fn,
  opts
)
  vim.api.nvim_create_user_command(deprecated_name, function(...)
    vim.notify(
      "Command '"
        .. deprecated_name
        .. "' is deprecated. Use '"
        .. new_name
        .. "' instead.",
      vim.log.levels.WARN
    )
    return cmd_fn(...)
  end, opts)

  vim.api.nvim_create_user_command(new_name, cmd_fn, opts)
end

local function setup_commands()
  local function flash(count, wait, seg, highlight, after)
    vim.defer_fn(function()
      if count == 0 then
        after()
        return
      end

      if count % 2 == 0 then
        seg.highlight(highlight)
      else
        seg.clear_hl()
      end

      return flash(count - 1, wait, seg, highlight, after)
    end, wait)
  end

  vim.api.nvim_create_user_command('Mcancel', function()
    local seg = segment.query(util.cursor.position())

    seg.highlight('Special')

    local cancel = seg.data.cancel

    if cancel ~= nil then
      cancel()
    else
      vim.notify('Not cancellable', vim.log.levels.WARN)
    end
  end, {
    range = true,
    desc = 'Cancel the completion under the cursor',
    force = true,
  })

  vim.api.nvim_create_user_command('Mdelete', function()
    local seg = segment.query(util.cursor.position())
    if seg then
      flash(6, 80, seg, 'DiffDelete', function()
        seg.delete()
      end)
    end
  end, {
    range = true,
    desc = 'Delete the completion under the cursor, replacing with original text if replacement',
    force = true,
  })

  vim.api.nvim_create_user_command('Mshow', function()
    local segs = segment.query_all(util.cursor.position())
    if #segs then
      for _, seg in ipairs(segs) do
        if seg.data then
          if seg.data.info then -- streaming thoughts?
            -- TODO probably make this seg.data.thinking
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
            local win = vim.api.nvim_open_win(buf, true, {
              relative = 'cursor',
              width = 80,
              height = 20,
              row = 1,
              col = 0,
              style = 'minimal',
              border = 'single',
            })

            local stop
            do
              stop = juice.animate(function()
                if not vim.api.nvim_win_is_valid(win) then
                  stop()
                  return
                end

                vim.api.nvim_buf_set_lines(
                  buf,
                  0,
                  -1,
                  false,
                  vim.split(seg.data.info, '\n')
                )
              end, 250)

              -- Close window when it loses focus
              vim.api.nvim_create_autocmd('WinLeave', {
                buffer = buf,
                once = true,
                callback = function()
                  if vim.api.nvim_win_is_valid(win) then
                    vim.api.nvim_win_close(win, true)
                  end
                  stop()
                end,
              })
            end
            break
          elseif seg.data.chat then
            chat.create_buffer(
              chat.to_string(seg.data.chat.contents, seg.data.chat.chat)
            )
            break
          end
        end
      end
    else
      util.eshow('No segment here')
    end
  end, {
    range = true,
    force = true,
    desc = 'Show the completion under the cursor. If it has info, show in preview.',
  })

  vim.api.nvim_create_user_command('Mselect', function()
    local seg = segment.query(util.cursor.position())

    if seg == nil then
      return
    end

    local details = seg.details()

    local start = {
      row = details.row,
      col = details.col,
    }

    local stop = {
      row = details.details.end_row,
      col = details.details.end_col,
    }

    local visual_select_keys = util.cursor.place_with_keys(start)
      .. 'v'
      .. util.cursor.place_with_keys(stop)

    vim.api.nvim_feedkeys(visual_select_keys, 'n', true)
  end, {
    force = true,
    desc = 'Select the completion under the cursor',
  })

  vim.api.nvim_create_user_command('M', command_request_completion, {
    range = true,
    desc = 'Request completion of selection',
    force = true,
    nargs = '*',
    complete = scopes.complete_arglead_prompt_names,
  })

  vim.api.nvim_create_user_command('Model', command_request_completion, {
    range = true,
    desc = 'Request completion of selection',
    force = true,
    nargs = '*',
    complete = scopes.complete_arglead_prompt_names,
  })

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
    end,
  }

  vim.api.nvim_create_user_command('Mstore', function(a)
    -- local args = a.fargs
    local command = a.fargs[1]

    local handler = handle_store_command[command]
    if handler == nil then
      error('Unknown Mstore command ' .. command)
    else
      return handler(a)
    end
  end, {
    desc = 'Mstore',
    force = true,
    nargs = '+',
    complete = function(arglead)
      return vim.fn.matchfuzzy(vim.tbl_keys(handle_store_command), arglead)
    end,
  })

  local function complete_chat_names(arglead)
    local chats = M.opts.chats
    if chats == nil then
      return
    end

    local chat_names = {}

    for name in util.module.autopairs(chats) do
      local name_ = name:gsub(' ', '\\ ')
      table.insert(chat_names, name_)
    end

    if #arglead == 0 then
      return chat_names
    end

    return vim.fn.matchfuzzy(chat_names, arglead)
  end

  vim.api.nvim_create_user_command(
    'MchatCompletionContinue',
    function(cmd_params)
      local instructions = table.concat(cmd_params.fargs, ' ')

      chat.continue_chat_completion(M.opts, instructions)
    end,
    {
      nargs = '+',
    }
  )

  vim.api.nvim_create_user_command('MchatCompletion', function(cmd_params)
    local chat_name = table.remove(cmd_params.fargs, 1)
    local instructions = table.concat(cmd_params.fargs, ' ')

    if chat_name ~= nil and chat_name ~= '' then
      local chat_prompt = assert(
        vim.tbl_get(M.opts, 'chats', chat_name),
        'Chat "' .. chat_name .. '" not found'
      )

      local want_visual_selection = cmd_params.range ~= 0

      local source = input.get_source(want_visual_selection)
      local input_context = input.get_input_context(source, instructions)
      local chat_contents = chat.build_contents(chat_prompt, input_context)

      chat.start_chat_completion({
        contents = chat_contents,
        chat = chat_name,
      }, chat_prompt, source)
    end
  end, {
    desc = 'Complete using a chat handler',
    force = true,
    range = true,
    nargs = '*',
    complete = complete_chat_names,
  })

  vim.api.nvim_create_user_command('Mchat', function(cmd_params)
    local chat_name = table.remove(cmd_params.fargs, 1)
    local args = table.concat(cmd_params.fargs, ' ')

    if chat_name ~= nil and chat_name ~= '' then -- `:Mchat [name]`
      local chat_prompt = assert(
        vim.tbl_get(M.opts, 'chats', chat_name),
        'Chat prompt "' .. chat_name .. '" not found in setup({chats = {..}})'
      )

      local input_context = input.get_input_context(
        input.get_source(cmd_params.range ~= 0), -- want_visual_selection
        args
      )

      if vim.o.ft == 'mchat' then
        -- copy current messages to a new built buffer with target settings
        local current = chat.parse(vim.api.nvim_buf_get_lines(0, 0, -1, false))

        local target = chat.build_contents(chat_prompt, input_context)

        if args == '-' then -- if args is `-`, use the current system instruction
          target.config.system = current.contents.config.system
        elseif args ~= '' then -- if args is not empty, use that as system instruction
          target.config.system = args
        end

        chat.create_buffer(
          chat.to_string({
            config = target.config,
            messages = current.contents.messages,
          }, chat_name),
          cmd_params.smods
        )
      else
        local chat_contents = chat.build_contents(chat_prompt, input_context)

        if args ~= '' then
          chat_contents.config.system = args
        end

        chat.create_buffer(
          chat.to_string(chat_contents, chat_name),
          cmd_params.smods
        )
      end
    else -- `:Mchat`
      if vim.o.ft ~= 'mchat' then
        error(
          'Not in mchat buffer. Either `:set ft=mchat` or run `:Mchat [name]`.'
        )
      end

      -- TODO REMOVE
      util.eshow(
        'Use `:MchatRun` to run the current chat. `:Mchat` to run chats is deprecated.'
      )

      chat.run_chat(M.opts)
    end
  end, {
    desc = 'Mchat',
    force = true,
    range = true,
    nargs = '*',
    complete = complete_chat_names,
  })

  vim.api.nvim_create_user_command('Mcount', function()
    local count = require('model.store.util').tiktoken_count
    local text = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    if vim.o.ft == 'mchat' then
      local parsed = chat.parse(text)
      local total = count(vim.json.encode(parsed.contents.messages))

      if parsed.contents.config.system then
        total = total + count(parsed.contents.config.system)
      end

      util.show(total)
    else
      util.show(count(table.concat(text, '\n')))
    end
  end, {})

  vim.api.nvim_create_user_command('Myank', function(opts)
    files.yank_with_line_numbers_and_filename(
      opts.args,
      opts.range == 2 and { start = opts.line1, stop = opts.line2 } or nil
    )
  end, {
    range = true,
    nargs = '?',
  })

  local qflist = require('model.util.qflist')

  vim.api.nvim_create_user_command('MCadd', function()
    qflist.add()
  end, {})
  vim.api.nvim_create_user_command('MCremove', function()
    qflist.remove()
  end, {})
  vim.api.nvim_create_user_command('MCclear', qflist.clear, {})
  vim.api.nvim_create_user_command('MCpaste', function()
    vim.api.nvim_put(vim.fn.split(qflist.get_text(), '\n'), 'l', true, true)
  end, {})
  vim.api.nvim_create_user_command('Mterm', function(opts)
    local cmd = table.concat(opts.fargs or {}, ' ')
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, 'scrollback', 1)
    vim.api.nvim_set_current_buf(buf)
    vim.fn.termopen(cmd)
    vim.cmd('startinsert')
    qflist.add(buf)
  end, {
    nargs = '*',
    desc = 'Open terminal with scrollback=1 and add to qflist',
  })
end

local function setup_treesitter_info()
  local parser_config = require('nvim-treesitter.parsers').get_parser_configs()
  parser_config.mchat = {
    install_info = {
      url = 'https://github.com/gsuuon/tree-sitter-mchat.git',
      files = { 'src/parser.c' },
      branch = 'main',
      generate_requires_npm = false,
      requires_generate_from_grammar = false,
    },
  }
end

---@class SetupOptions
---@field default_prompt? Prompt default = openai. The default prompt (`:M` or `:Model` with no argument)
---@field prompts? table<string, Prompt> default = starters. Add prompts (`:M [name]`)
---@field chats? table<string, ChatPrompt> default = prompts/chats. Add chat prompts (`:MChat [name]`)
---@field hl_group? string default = 'Comment'. Set the default highlight group of in-progress responses
---@field join_undo? boolean default = true. Join streaming response text as a single `u` undo. Edits during streaming will also be undone.
---@field secrets? fun(key: string): string | table<string, fun(): string> Secret generator or dictionary of secret generators. Used by `util.env(keyname)`. Value will fallback to env variable.

---@param opts? SetupOptions
function M.setup(opts)
  M.opts = vim.tbl_extend('force', {
    default_prompt = require('model.providers.openai').default_prompt,
    prompts = require('model.prompts.starters'),
    chats = require('model.prompts.chats'),
    tools = require('model.tools'),
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

  if M.opts.secrets then
    util.secrets = M.opts.secrets
  end

  setup_commands()

  pcall(setup_treesitter_info)

  vim.g.did_setup_model = true
end

M.mode = provider.mode -- convenience export

return M
