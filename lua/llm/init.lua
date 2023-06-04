local segment = require('llm.segment')
local util = require('llm.util')

---@alias PromptBuilder fun(input: string, context: table): table Converts input and context to request data

---@class Provider
---@field request_completion_stream fun(input: string, handler: StreamHandlers, builder: PromptBuilder, params?: table): nil Request a completion stream from provider

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

local M = {}

---@class GetInputSegmentBehavior
---@field get_visual_selection boolean
---@field segment_mode SegmentMode

---@class Segment
---@field add fun(text: string): nil
---@field clear_hl fun(): nil
---@field data table
---@field highlight fun(hl_group: string): nil

local get_input = {
  visual_selection = function()
    local selection = util.cursor.selection()
    local lines = util.buf.text(selection)

    return {
      selection = selection,
      lines = lines
    }
  end,

  file = function ()
    return {
      lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    }
  end
}

---@param behavior GetInputSegmentBehavior
---@param hl_group string
---@return { input: string, segment: Segment }
local function get_input_and_segment(behavior, hl_group)
  -- TODO dry

  local bufnr = vim.fn.bufnr('%')

  if behavior.segment_mode == segment.mode.REPLACE then
    if behavior.get_visual_selection then
      local input = get_input.visual_selection()

      util.buf.set_text(input.selection, {})

      local seg = segment.create_segment_at(
        input.selection.start.row,
        input.selection.start.col,
        hl_group,
        bufnr
      )

      seg.data.original = input.lines

      return {
        input = input.lines,
        segment = seg
      }
    else
      local input = get_input.file()
      local seg = segment.create_segment_at(0, 0, hl_group, bufnr)

      vim.api.nvim_buf_set_lines(0, 0, -1, false, {})

      seg.data.original = input.lines

      return {
        input = input.lines,
        segment = seg
      }
    end
  end

  if behavior.segment_mode == segment.mode.APPEND then
    if behavior.get_visual_selection then
      local input = get_input.visual_selection()

      local seg = segment.create_segment_at(
        input.selection.stop.row,
        input.selection.stop.col,
        hl_group,
        bufnr
      )

      return {
        input = input.lines,
        segment = seg
      }
    else
      local input = get_input.file()
      local seg = segment.create_segment_at(#input.lines, 0, hl_group, bufnr)

      return {
        input = input.lines,
        segment = seg
      }
    end
  end

  if behavior.segment_mode == segment.mode.BUFFER then
    -- get the llm buffer
    -- split it if not visible?
    -- create segment at end of buffer
  end

  error('Unknown mode')
end

---@param input string | string[]
---@param prompt Prompt
---@param handlers StreamHandlers
---@param args string
local function start_prompt(input, prompt, handlers, args)
  local _input = type(input) == 'table' and table.concat(input, '\n') or input

  local success, pcall_result = pcall(prompt.provider.request_completion_stream, _input, handlers, prompt.builder, prompt.params, args)

  local result = {
    started = success
  }

  if success then
    result.cancel = pcall_result
  else
    result.error = pcall_result
  end

  return result
end

local function request_completion_input_segment(input_segment, prompt, args)
  local seg = input_segment.segment

  local proc = start_prompt(input_segment.input, prompt, {
    on_partial = function(partial)
      seg.add(partial)
    end,

    on_finish = function(_, reason)
      if reason == 'stop' then
        seg.clear_hl()
      elseif reason == 'length' then
        seg.highlight('Error')
        util.eshow('Hit token limit')
      else
        seg.highlight('Error')
        util.eshow('Response ended because: ' .. reason)
      end
    end,

    on_error = function(data, label)
      util.eshow(data, 'stream error ' .. label)
    end
  }, args)

  if proc.started then
    seg.data.cancel = proc.cancel
  else
    util.eshow(proc.error, 'process')
  end
end

function M.request_completion_stream(cmd_params)

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
  local prompt_mode = prompt.mode or segment.mode.APPEND
  local want_visual_selection = cmd_params.range ~= 0

  if type(prompt.mode) == 'table' then
    ---@cast prompt_mode StreamHandlers

    local input =
      want_visual_selection and get_input.visual_selection() or get_input.file()

    local result = start_prompt(
      input.lines,
      prompt,
      prompt_mode,
      args
    )

    if not result.started then
      util.eshow(result.error)
      -- TODO what can we do with result.cancel?
    end

    return
  end

  ---@cast prompt_mode SegmentMode
  local input_segment = get_input_and_segment(
    {
      get_visual_selection = want_visual_selection,
      segment_mode = prompt_mode
    },
    prompt.hl_group or M.opts.hl_group
  )

  request_completion_input_segment(input_segment, prompt, args)

end

function M.request_multi_completion_streams(cmd_params)
  local prompt_names = cmd_params.fargs

  local prompts = vim.tbl_map(function(name)
    return assert(M.opts.prompts[name], "Prompt '" .. name .. "' wasn't found")

  end, prompt_names)

  for i, prompt in ipairs(prompts) do
    local input_segment = get_input_and_segment(
      {
        get_visual_selection = false, -- multi-mode always treated as line-wise
        segment_mode = segment.mode.APPEND -- multi-mode always append only
      },
      prompt.hl_group or M.opts.hl_group
    )

    -- try to avoid ratelimits
    vim.defer_fn(function()
      request_completion_input_segment(input_segment, prompt)
    end, i * 200)
  end
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

  vim.api.nvim_create_user_command('LlmMulti', M.request_multi_completion_streams, {
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

        if cancel ~= nil then cancel() end
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

  vim.api.nvim_create_user_command('Llm', M.request_completion_stream, {
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

