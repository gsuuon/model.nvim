local segment = require("llm.segment")
local util = require("llm.util")

---@alias PromptBuilder fun(input: string, context: table): table Converts input and context to request data

---@class Provider
---@field request_completion_stream fun(input: string, handler: StreamHandlers, builder: PromptBuilder, params?: table): nil Request a completion stream from provider

---@class Prompt
---@field provider Provider The API provider for this prompt
---@field builder PromptBuilder Converts input and context to request data
---@field hl_group? string Highlight group of active response


---@class StreamHandlers
---@field on_partial (fun(partial_text: string): nil)
---@field on_finish (fun(complete_text: string, finish_reason: string): nil)
---@field on_error (fun(data: any, label: string): nil) }
--
local M = {}

local function get_input_and_segment(no_selection, hl_group)
  if no_selection then
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local seg = segment.create_segment_at(#lines, 0, hl_group)

    return {
      input = table.concat(lines, '\n'),
      segment = seg
    }
  else
    local selection = util.cursor.selection()
    local text = util.buf.text(selection)

    local seg = segment.create_segment_at(
      selection.stop.row,
      selection.stop.col,
      hl_group
    )

    return {
      input = text,
      segment = seg
    }
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

  local no_selection = cmd_params.range == 0

  local input_segment = get_input_and_segment(no_selection, prompt.hl_group or M.opts.hl_group)
  local seg = input_segment.segment

  local success, result = pcall(prompt.provider.request_completion_stream, input_segment.input, {
    on_partial = function(partial)
      seg.add(partial)
    end,

    on_finish = function(_, reason)
      if reason == 'stop' then
        seg.close()
      else
        seg.highlight("Error")
      end
    end,

    on_error = function(data, label)
      util.eshow(data, 'stream error ' .. label)
    end
  }, prompt.builder)

  if not success then
    util.eshow(result)
  end
end

function M.commands(opts)
  vim.api.nvim_create_user_command("Llm", M.request_completion_stream, {
    range = true,
    desc = "Request completion of selection",
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
    hl_group = "Comment",
  }

  if opts.default_prompt == nil then
    local openai = require("llm.providers.openai")

    _opts.default_prompt = {
      provider = openai,
      builder = openai.default_builder
    }
  end

  if opts ~= nil then
    _opts = vim.tbl_deep_extend("force", _opts, opts)
  end

  M.opts = _opts
  M.commands(_opts)
end

return M

