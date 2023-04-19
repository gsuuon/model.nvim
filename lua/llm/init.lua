local segment = require('llm.segment')
local util = require('llm.util')

---@alias PromptBuilder fun(input: string, context: table): table Converts input and context to request data

---@class Provider
---@field request_completion_stream fun(input: string, handler: StreamHandlers, builder: PromptBuilder, params?: table): nil Request a completion stream from provider

---@class Prompt
---@field provider Provider The API provider for this prompt
---@field builder PromptBuilder Converts input and context to request data
---@field hl_group? string Highlight group of active response
---@field mode? SegmentMode Response replacement mode ("replace" | "append"). Defaults to "append".

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

---@param behavior GetInputSegmentBehavior
---@param hl_group string
---@return { input: string, segment: Segment }
local function get_input_and_segment(behavior, hl_group)
  -- TODO dry

  if behavior.segment_mode == segment.mode.REPLACE then
    if behavior.get_visual_selection then
      local selection = util.cursor.selection()
      local lines = util.buf.text(selection)

      util.buf.set_text(selection, {})

      local seg = segment.create_segment_at(
        selection.start.row,
        selection.start.col,
        hl_group
      )

      seg.data.original = lines

      return {
        input = table.concat(lines, '\n'),
        segment = seg
      }
    else
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local seg = segment.create_segment_at(0, 0, hl_group)
      local text = table.concat(lines, '\n') -- TODO use the original separator in file

      vim.api.nvim_buf_set_lines(0, 0, -1, false, {})

      seg.data.original = lines

      return {
        input = text,
        segment = seg
      }
    end
  end

  if behavior.segment_mode == segment.mode.APPEND then
    if behavior.get_visual_selection then
      local selection = util.cursor.selection()
      local lines = util.buf.text(selection)

      local seg = segment.create_segment_at(
        selection.stop.row,
        selection.stop.col,
        hl_group
      )

      return {
        input = table.concat(lines, '\n'),
        segment = seg
      }
    else
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local seg = segment.create_segment_at(#lines, 0, hl_group)

      return {
        input = table.concat(lines, '\n'),
        segment = seg
      }
    end
  end

  error('Unknown mode')
end

local function request_completion_input_segment(input_segment, prompt)
  local seg = input_segment.segment

  local success, result = pcall(prompt.provider.request_completion_stream, input_segment.input, {
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
  }, prompt.builder)

  if success then
    local cancel = result

    seg.data.cancel = cancel
  else
    util.eshow(result)
  end
end

function M.request_completion_stream(cmd_params)

  ---@return Prompt
  local function get_prompt()
    local prompt_arg = cmd_params.fargs[1]

    if not prompt_arg then
      return M.opts.default_prompt
    end

    return assert(M.opts.prompts[prompt_arg], "Prompt '" .. prompt_arg .. "' wasn't found")
  end

  local prompt = get_prompt()

  local input_segment = get_input_and_segment(
    {
      get_visual_selection = cmd_params.range ~= 0,
      segment_mode = prompt.mode or segment.mode.APPEND
    },
    prompt.hl_group or M.opts.hl_group
  )

  request_completion_input_segment(input_segment, prompt)

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
    nargs='?',
    complete = function(arglead)
      local prompt_names = {}

      for k, _ in util.module.autopairs(opts.prompts) do
        table.insert(prompt_names, k)
      end

      if #arglead == 0 then return prompt_names end

      return vim.fn.matchfuzzy(prompt_names, arglead)
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

