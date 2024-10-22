local segment = require('model.util.segment')
local util = require('model.util')
local input = require('model.core.input')

local M = {}

---@class Prompt
---@field provider Provider The API provider for this prompt
---@field builder ParamsBuilder Converts input and context to request params. Input is either the visual selection if there is one or the entire buffer text.
---@field transform? fun(string): string Transforms the completed response text after on_finish, e.g. to extract code
---@field mode? SegmentMode | StreamHandlers Response handling mode. Defaults to 'append'.
---@field hl_group? string Highlight group of active response
---@field params? table Static request parameters
---@field options? table Options for the provider

---@class Provider
---@field request_completion fun(handler: StreamHandlers, params?: table, options?: table): function Request a completion stream from provider, returning a cancel callback. Call the handler methods to feed the completion parts back to the prompt runner, and call on_finish after the completion is done.
---@field default_prompt? Prompt
---@field adapt? fun(prompt: StandardPrompt): table Adapt a standard prompt to params for this provider

---@alias ParamsBuilder fun(input: string, context: Context): table | fun(resolve: fun(params: table)) Converts input and context to request data. Returns the params to use for this request or a function that takes a callback which should be called with the params for this request.

---@enum SegmentMode
M.mode = {
  APPEND = 'append', -- append to the end of input
  REPLACE = 'replace', -- replace input
  BUFFER = 'buffer', -- create a new buffer and insert
  INSERT = 'insert', -- insert at the cursor position
  INSERT_OR_REPLACE = 'insert_or_replace', -- insert at the cursor position if no selection, or replace the selection
}

---@class StreamHandlers
---@field on_partial (fun(partial_text: string): nil) Partial response of just the diff
---@field on_finish (fun(complete_text?: string, finish_reason?: string): nil) Complete response with finish reason. When implementing a provider you can call this with with no arguments to just finish with the concatenated partials. Finish reason should be 'stop' or nil for a successful completion.
---@field on_error (fun(data: any, label?: string): nil) Error data and optional label
---@field segment? Segment The segment handling the response, if existing

local function create_segment(source, segment_mode, hl_group)
  if segment_mode == M.mode.REPLACE then
    if source.selection ~= nil then
      -- clear selection
      util.buf.set_text(source.selection, {})
      local seg = segment.create_segment_at(
        source.selection.start.row,
        source.selection.start.col,
        hl_group,
        0
      )

      seg.data.original = source.lines

      return seg
    else
      -- clear buffer
      local seg = segment.create_segment_at(0, 0, hl_group, 0)

      vim.api.nvim_buf_set_lines(0, 0, -1, false, {})

      seg.data.original = source.lines

      return seg
    end
  elseif segment_mode == M.mode.APPEND then
    if source.selection ~= nil then
      return segment.create_segment_at(
        source.selection.stop.row,
        source.selection.stop.col,
        hl_group,
        0
      )
    else
      return segment.create_segment_at(#source.lines, 0, hl_group, 0)
    end
  elseif segment_mode == M.mode.BUFFER then
    vim.cmd.vnew()

    vim.api.nvim_set_option_value('buflisted', true, { scope = 'local' })
    vim.api.nvim_set_option_value('buftype', 'nowrite', { scope = 'local' })

    table.insert(source.lines, '')

    vim.api.nvim_buf_set_lines(0, -2, -1, false, source.lines)

    -- Create a segment at the end of the buffer
    local line_count = vim.api.nvim_buf_line_count(0)
    return segment.create_segment_at(line_count, 0, hl_group, 0)
  elseif segment_mode == M.mode.INSERT then
    local pos = util.cursor.position()

    return segment.create_segment_at(pos.row, pos.col, hl_group, 0)
  else
    error('Unknown segment mode: ' .. segment_mode)
  end
end

---@param prompt Prompt
---@param handlers StreamHandlers
---@param input_context InputContext
---@return function cancel callback
local function build_params_run_prompt(prompt, handlers, input_context)
  -- TODO args to prompts is probably less useful than the prompt buffer / helper

  local function do_request(built_params)
    local params = vim.tbl_extend('force', (prompt.params or {}), built_params)

    return prompt.provider.request_completion(handlers, params, prompt.options)
  end

  local prompt_built = assert(
    prompt.builder(input_context.input, input_context.context),
    'prompt builder produced nil'
  )

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

---@param prompt Prompt
---@param seg Segment
local function create_prompt_handlers(prompt, seg)
  local completion = ''

  return {
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
      util.eshow(data, label or 'Stream error ')
    end,

    segment = seg,
  }
end

---@param prompt Prompt
---@param input_context InputContext
---@param source Source
local function create_segment_handlers_run_prompt(prompt, input_context, source)
  local mode = (function()
    if prompt.mode == M.mode.INSERT_OR_REPLACE then
      if source.selection then
        return M.mode.REPLACE
      else
        return M.mode.INSERT
      end
    end

    return prompt.mode or M.mode.APPEND
  end)()

  local seg = create_segment(source, mode, prompt.hl_group)

  seg.data.cancel = build_params_run_prompt(
    prompt,
    create_prompt_handlers(prompt, seg),
    input_context
  )
end

---@type Context
local empty_context = {
  before = '',
  after = '',
  filename = '',
  args = '',
  selection = nil,
}

-- Run a prompt and resolve the complete result. Does not do anything with the result (ignores prompt mode)
---@param prompt Prompt
---@param input_context { input: string, context?: Context }
---@param callback fun(completion: string) completion callback
function M.complete(prompt, input_context, callback)
  return build_params_run_prompt(prompt, {
    on_partial = function() end,
    on_finish = function(complete_text)
      callback(complete_text)
    end,
    on_error = function(data, label)
      util.eshow(data, label or 'Request error')
    end,
  }, {
    input = input_context.input,
    context = input_context.context or empty_context,
  })
end

---@param prompt Prompt
---@param args string
---@param want_visual_selection boolean
function M.request_completion(prompt, args, want_visual_selection)
  local source = input.get_source(want_visual_selection)

  if type(prompt.mode) == 'table' then -- prompt_mode is StreamHandlers
    -- TODO probably want to just remove streamhandlers prompt mode

    local stream_handlers = prompt.mode
    ---@cast stream_handlers StreamHandlers

    build_params_run_prompt(
      prompt,
      stream_handlers,
      input.get_input_context(source, args)
    )
  else
    create_segment_handlers_run_prompt(
      prompt,
      input.get_input_context(source, args),
      source
    )
  end
end

function M.request_multi_completion_streams(prompts, want_visual_selection)
  for i, prompt in ipairs(prompts) do
    -- try to avoid ratelimits
    vim.defer_fn(function()
      local source = input.get_source(want_visual_selection)

      create_segment_handlers_run_prompt(
        vim.tbl_extend('force', prompt, {
          mode = M.mode.APPEND, -- multi-mode always append only
        }),
        input.get_input_context(source, ''),
        source
      )
    end, i * 200)
  end
end

return M
