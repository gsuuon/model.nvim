local segment = require('llm.segment')
local util = require('llm.util')

local M = {}

---@class Prompt
---@field provider Provider The API provider for this prompt
---@field builder ParamsBuilder Converts input and context to request params
---@field transform fun(string): string Transforms response text after completion finishes
---@field mode? SegmentMode | StreamHandlers Response handling mode. Defaults to "append".
---@field hl_group? string Highlight group of active response
---@field params? table Additional static parameters to add to request body - ParamsBuilder data is merged into and overrides this.
---@field options? table Options for the provider

---@class Provider
---@field request_completion fun(handler: StreamHandlers, params?: table, options?: table): function Request a completion stream from provider, returning a cancel callback
---@field default_prompt? Prompt
---@field adapt? fun(prompt: StandardPrompt): table Adapt a standard prompt to params for this provider

---@alias ParamsBuilder fun(input: string, context: Context): table | fun(resolve: fun(results: table)) Converts input and context to request data. Returns a table of results or a function that takes a resolve function taking a table of results.

---@enum SegmentMode
M.mode = {
  APPEND = "append",
  REPLACE = "replace",
  BUFFER = "buffer",
  INSERT = "insert",
  INSERT_OR_REPLACE = "insert_or_replace"
}

---@class StreamHandlers
---@field on_partial (fun(partial_text: string): nil) Partial response of just the diff
---@field on_finish (fun(complete_text?: string, finish_reason?: string): nil) Complete response with finish reason. Leave complete_text nil to just use concatenated partials.
---@field on_error (fun(data: any, label?: string): nil) Error data and optional label

local function get_segment(input, segment_mode, hl_group)
  if segment_mode == M.mode.REPLACE then
    if input.selection ~= nil then
      -- clear selection
      util.buf.set_text(input.selection, {})
      local seg = segment.create_segment_at(
        input.selection.start.row,
        input.selection.start.col,
        hl_group,
        0
      )

      seg.data.original = input.lines

      return seg
    else
      -- clear buffer
      local seg = segment.create_segment_at(0, 0, hl_group, 0)

      vim.api.nvim_buf_set_lines(0, 0, -1, false, {})

      seg.data.original = input.lines

      return seg
    end
  elseif segment_mode == M.mode.APPEND then
    if input.selection ~= nil then
      return segment.create_segment_at(
        input.selection.stop.row,
        input.selection.stop.col,
        hl_group,
        0
      )
    else
      return segment.create_segment_at(#input.lines, 0, hl_group, 0)
    end
  elseif segment_mode == M.mode.BUFFER then
    -- Find or create a scratch buffer for this plugin
    local bufname = '__llm__'
    local llm_bfnr = vim.fn.bufnr(bufname, true)

    if llm_bfnr == -1 then
      llm_bfnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_name(llm_bfnr, bufname)
    end

    vim.api.nvim_buf_set_option(llm_bfnr, 'buflisted', true)
    vim.api.nvim_buf_set_option(llm_bfnr, 'buftype', 'nowrite')

    vim.api.nvim_buf_set_lines(llm_bfnr, -2, -1, false, input.lines)
    vim.api.nvim_buf_set_lines(llm_bfnr, -1, -1, false, {'',''})

    -- Open the existing buffer or create a new one
    vim.api.nvim_set_current_buf(llm_bfnr)

    -- Create a segment at the end of the buffer
    local line_count = vim.api.nvim_buf_line_count(llm_bfnr)
    return segment.create_segment_at(line_count, 0, hl_group, llm_bfnr)
  elseif segment_mode == M.mode.INSERT then
    local pos = util.cursor.position()

    return segment.create_segment_at(pos.row, pos.col, hl_group, 0)
  else
    error('Unknown segment mode: ' .. segment_mode)
  end
end

local function get_input(want_visual_selection)
  if want_visual_selection then
    local selection = util.cursor.selection()
    local lines = util.buf.text(selection)

    return {
      selection = selection,
      position = util.cursor.position(),
      lines = lines
    }
  else
    return {
      position = util.cursor.position(),
      lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    }
  end
end

local function get_before_after(input)
  return {
    before = util.buf.text({
      start = {
        row = 0,
        col = 0
      },
      stop = input.selection ~= nil and input.selection.start or input.position
    }),
    after = util.buf.text({
      start = input.selection ~= nil and input.selection.stop or input.position,
      stop = {
        row = -1,
        col = -1
      },
    })
  }
end

---@class Context
---@field before string
---@field after string
---@field filename string
---@field args string
---@field segment Segment

---@class RequestCompletionHandleParams
---@field input string[]
---@field context Context

---@param segment_mode SegmentMode
---@param want_visual_selection boolean
---@param hl_group string
---@param args string
---@return RequestCompletionHandleParams
local function build_request_handle_params(segment_mode, want_visual_selection, hl_group, args)
  -- TODO is args actually useful here?

  local function seg_mode(mode, selection)
    if mode == M.mode.INSERT_OR_REPLACE then
      if selection then
        return M.mode.REPLACE
      else
        return M.mode.INSERT
      end
    end

    return mode
  end

  local input = get_input(want_visual_selection)
  local before_after = get_before_after(input)
  local seg = get_segment(input, seg_mode(segment_mode, want_visual_selection), hl_group)

  return {
    input = input.lines,
    context = {
      segment = seg,
      selection = input.selection,
      filename = util.buf.filename(),
      before = before_after.before,
      after = before_after.after,
      args = args,
    }
  }
end

---@param input string | string[]
---@param prompt Prompt
---@param handlers StreamHandlers
---@param context Context
---@return function cancel callback
local function start_prompt(input, prompt, handlers, context)
  -- TODO args to prompts is probably less useful than the prompt buffer / helper

  local function as_string(str_or_strs)
    if type(input) == 'string' then
      return str_or_strs
    else
      return table.concat(str_or_strs, '\n')
    end
  end

  local prompt_built = assert(prompt.builder(as_string(input), context), 'prompt builder produced nil')

  local function do_request(built_params)
    local params = vim.tbl_extend(
      'force',
      (prompt.params or {}),
      built_params
    )

    return prompt.provider.request_completion(handlers, params, prompt.options)
  end

  if type(prompt_built) == 'function' then
    local cancel

    prompt_built(function(prompt_params)
      -- x are the built params here
      cancel = do_request(prompt_params)
    end)

    return function()
      cancel()
    end
  else
    return do_request(prompt_built)
  end
end

local function request_completion_input_segment(handle_params, prompt)
  local seg = handle_params.context.segment

  local completion = ""

  local cancel = start_prompt(handle_params.input, prompt, {
    on_partial = function(partial)
      completion = completion .. partial
      seg.add(partial)
    end,

    on_finish = function(complete_text, reason)
      if complete_text == nil or string.len(complete_text) == 0 then
        complete_text = completion
      end

      if prompt.transform == nil then
        seg.set_text(complete_text)
      else
        seg.set_text(prompt.transform(complete_text))
      end

      if reason == nil or reason == 'stop' then
        seg.clear_hl()
      elseif reason == 'length' then
        seg.highlight('Error')
        util.eshow('Hit token limit')
      else
        seg.highlight('Error')
        util.eshow('Response ended because: ' .. reason)
      end

      if prompt.mode == M.mode.BUFFER then
        seg.highlight('Identifier')
      end
    end,

    on_error = function(data, label)
      util.eshow(data, 'stream error ' .. (label or ''))
    end
  }, handle_params.context)

  seg.data.cancel = cancel
end

-- Run a prompt and resolve the complete result. Does not do anything with the result (ignores prompt mode)
function M.complete(prompt, input, context, callback)
  local cancel = start_prompt(input, prompt, {
    on_partial = function() end,

    on_finish = function(complete_text)
      callback(complete_text)
    end,

    on_error = function(data, label)
      util.eshow(data, 'stream error ' .. (label or ''))
    end
  }, context)

  return cancel
end

---@param prompt Prompt
---@param args string
---@param want_visual_selection boolean
function M.request_completion(prompt, args, want_visual_selection, default_hl_group)
  local prompt_mode = prompt.mode or M.mode.APPEND

  if type(prompt_mode) == 'table' then -- prompt_mode is StreamHandlers
    -- TODO probably want to just remove streamhandlers prompt mode
    local stream_handlers = prompt_mode

    local handle_params = build_request_handle_params(
      M.mode.APPEND, -- we don't use the segment here, append will create an empty segment at end of selection
      want_visual_selection,
      prompt.hl_group or default_hl_group,
      args
    )

    start_prompt(
      handle_params.input,
      prompt,
      stream_handlers,
      handle_params.context
    )

    return
  end

  ---@cast prompt_mode SegmentMode
  local handle_params = build_request_handle_params(
    prompt_mode,
    want_visual_selection,
    prompt.hl_group or default_hl_group,
    args
  )

  request_completion_input_segment(handle_params, prompt)
end

function M.request_multi_completion_streams(prompts, want_visual_selection, default_hl_group)
  for i, prompt in ipairs(prompts) do
    local handle_params = build_request_handle_params(
      M.mode.APPEND, -- multi-mode always append only
      want_visual_selection,
      prompt.hl_group or default_hl_group,
      ''
    )

    -- try to avoid ratelimits
    vim.defer_fn(function()
      request_completion_input_segment(handle_params, prompt)
    end, i * 200)
  end
end

return M
