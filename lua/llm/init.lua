local segment = require('llm.segment')
local util = require('llm.util')
local provider = require('llm.provider')

---@alias PromptBuilder fun(input: string, context: table): table | fun(resolve: fun(results: table)) Converts input and context to request data. Returns a table of results or a function that takes a resolve function taking a table of results.

---@class Provider
---@field request_completion_stream fun(handler: StreamHandlers, params?: table): function Request a completion stream from provider, returning a cancel callback

---@class Prompt
---@field provider Provider The API provider for this prompt
---@field builder PromptBuilder Converts input and context to request data
---@field hl_group? string Highlight group of active response
---@field mode? SegmentMode | StreamHandlers Response handling mode ("replace" | "append" | StreamHandlers). Defaults to "append".
---@field params? any Additional parameters to add to request body

---@class StreamHandlers
---@field on_partial (fun(partial_text: string): nil) Partial response of just the diff
---@field on_finish (fun(complete_text: string, finish_reason: string): nil) Complete response with finish reason
---@field on_error (fun(data: any, label?: string): nil) Error data and optional label

---@class Segment
---@field add fun(text: string): nil
---@field clear_hl fun(): nil
---@field data table
---@field highlight fun(hl_group: string): nil

local M = {}

local function command_request_completion_stream(cmd_params)
  ---@return Prompt, string
  local function get_prompt_and_args(args)
    local prompt_arg = table.remove(args, 1)

    if not prompt_arg then
      return M.opts.default_prompt, ''
    end

    local prompt = assert(M.opts.prompts[prompt_arg], "Prompt '" .. prompt_arg .. "' wasn't found")
    return prompt, table.concat(args, ' ')
  end

  local prompt, args = get_prompt_and_args(cmd_params.fargs)
  local want_visual_selection = cmd_params.range ~= 0

  return provider.request_completion_stream(prompt, args, want_visual_selection, M.opts.hl_group)
end

local function command_request_multi_completion_streams(cmd_params)
  local prompt_names = cmd_params.fargs

  local prompts = vim.tbl_map(function(name)
    return assert(M.opts.prompts[name], "Prompt '" .. name .. "' wasn't found")

  end, prompt_names)

  return provider.request_multi_completion_streams(prompts, M.opts.default_prompt)
end

function M.commands(opts)
  local function flash(count, wait, segments, highlight, after)
    vim.defer_fn(function ()
      if count == 0 then after() return end

      if count % 2 == 0 then
        for _, seg in ipairs(segments) do seg.highlight(highlight) end
      else
        for _, seg in ipairs(segments) do seg.clear_hl() end
      end

      return flash(count - 1, wait, segments, highlight, after)
    end, wait)
  end

  vim.api.nvim_create_user_command('LlmMulti', command_request_multi_completion_streams, {
    force = true,
    range = true,
    nargs = '+',
    desc = 'Request multiple prompts at the same time',
    complete = function(arglead)
      local prompt_names = {}

      for k, _ in util.module.autopairs(opts.prompts) do
        local escaped = k:gsub(" ", "\\ ")
        table.insert(prompt_names, escaped)
      end

      if #arglead == 0 then return prompt_names end

      return vim.fn.matchfuzzy(prompt_names, arglead)
    end
  })

  vim.api.nvim_create_user_command('LlmCancel',
    function()
      local matches = segment.query(util.cursor.position())

      for _, seg in ipairs(matches) do
        seg.highlight('Special')

        local cancel = seg.data.cancel

        if cancel ~= nil then
          cancel()
        else
          vim.notify('Not cancellable', vim.log.levels.WARN)
        end
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
      local matches = segment.query(util.cursor.position())

      flash(6, 80, matches, 'DiffDelete',
        function()
          for _, seg in ipairs(matches) do seg.delete() end
        end
      )
    end,
    {
      range = true,
      desc = 'Delete the completion under the cursor, replacing with original text if replacement',
      force = true
    }
  )

  vim.api.nvim_create_user_command('LlmShow',
    function()
      local matches = segment.query(util.cursor.position())

      flash(10, 80, matches, 'DiffChange', util.noop)
    end,
    {
      range = true,
      force = true,
      desc = 'Show the completion under the cursor'
    }
  )

  vim.api.nvim_create_user_command('Llm', command_request_completion_stream, {
    range = true,
    desc = 'Request completion of selection',
    force = true,
    nargs='*',
    complete = function(arglead)
      local prompt_names = {}

      for k, _ in util.module.autopairs(opts.prompts) do
        local escaped = k:gsub(" ", "\\ ")
        table.insert(prompt_names, escaped)
      end

      if #arglead == 0 then return prompt_names end

      return vim.fn.matchfuzzy(prompt_names, arglead)
    end
  })

  local store = require('llm.store.store')

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
end

function M.setup(opts)
  local _opts = {
    hl_group = 'Comment',
  }

  if (opts or {}).default_prompt == nil then
    local openai = require('llm.providers.openai')

    _opts.default_prompt = {
      provider = openai,
      builder = openai.default_builder
    }
  end

  if opts ~= nil then
    _opts = vim.tbl_deep_extend('force', _opts, opts)
  end

  M.opts = _opts
  M.commands(_opts)
end

return M

