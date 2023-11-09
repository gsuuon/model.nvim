local segment = require('llm.segment')
local util = require('llm.util')
local provider = require('llm.provider')
local scopes = require('llm.prompts.scopes')
local chat = require('llm.chat')

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

  local prompt, args = get_prompt_and_args(cmd_params.fargs)
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

  vim.api.nvim_create_user_command('LlmMulti', command_request_multi_completion_streams, {
    force = true,
    range = true,
    nargs = '+',
    desc = 'Request multiple prompts at the same time',
    complete = scopes.complete_arglead_prompt_names
  })

  vim.api.nvim_create_user_command('LlmCancel',
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

  vim.api.nvim_create_user_command('LlmDelete',
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

  vim.api.nvim_create_user_command('LlmShow',
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

  vim.api.nvim_create_user_command('LlmSelect',
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

  vim.api.nvim_create_user_command('Llm', command_request_completion, {
    range = true,
    desc = 'Request completion of selection',
    force = true,
    nargs='*',
    complete = scopes.complete_arglead_prompt_names
  })

  local store = require('llm.store')

  local handle_llm_store = {
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

  vim.api.nvim_create_user_command('LlmStore', function(a)
    -- local args = a.fargs
    local command = a.fargs[1]

    local handler = handle_llm_store[command]
    if handler == nil then
      error('Unknown LlmStore command ' .. command)
    else
      return handler(a)
    end
  end, {
      desc = 'LlmStore',
      force = true,
      nargs='+',
      complete = function(arglead)
        return vim.fn.matchfuzzy(vim.tbl_keys(handle_llm_store), arglead)
      end
    })

  vim.api.nvim_create_user_command(
    'LlmChat',
    function(cmd_params)
      local chat_name = cmd_params.fargs[1]

      if chat_name ~= nil and chat_name ~= '' then
        local want_visual_selection = cmd_params.range ~= 0

        chat.create_new_chat(
          M.opts,
          chat_name,
          want_visual_selection
        )
      else
        if vim.o.ft ~= 'llmchat' then
          error('Not in llmchat buffer')
        end

        chat.run_chat(M.opts)
      end
    end,
    {
      desc = 'LlmChat',
      force = true,
      range = true,
      nargs = '?',
      complete = function(arglead)
        local chats = M.opts.chats
        if chats == nil then return end

        local chat_names = vim.tbl_keys(chats)

        if #arglead == 0 then return chat_names end

        return vim.fn.matchfuzzy(chat_names, arglead)
      end
    })
end

function M.setup(opts)
  M.opts = vim.tbl_extend('force', {
    default_prompt = require('llm.providers.openai').default_prompt
  }, opts or {})

  if M.opts.prompts then
    scopes.set_global_user_prompts(M.opts.prompts)
  end

  if M.opts.join_undo then
    segment.join_undo = true
  end

  if M.opts.hl_group then
    segment.default_hl = M.opts.hl_group
  end

  setup_commands()

  vim.g.did_setup_llm = true
end

M.mode = provider.mode -- convenience export

return M

