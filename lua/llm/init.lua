local segment = require("llm.segment")
local util = require("llm.util")

local M = {}

local function get_prompt_and_segment(no_selection)
  if no_selection then
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local seg = segment.create_segment_at(#lines, 0, M.responding_hl_group)

    return {
      prompt = table.concat(lines, '\n'),
      segment = seg
    }
  else
    local selection = util.cursor.selection()
    local text = util.buf.text(selection)

    local seg = segment.create_segment_at(
      selection.stop.row,
      selection.stop.col,
      M.opts.responding_hl_group
    )

    return {
      prompt = text,
      segment = seg
    }
  end
end

---@class StreamHandlers
---@field on_partial (fun(partial_text: string): nil)
---@field on_finish (fun(complete_text: string, finish_reason: string): nil)
---@field on_error (fun(data: any, label: string): nil) }

function M.request_completion_stream(cmd_params)
  local no_selection = cmd_params.range == 0

  local prompt_segment = get_prompt_and_segment(no_selection)
  local seg = prompt_segment.segment

  local function get_prompt()
    local prompt_arg = cmd_params.fargs[1]

    if not prompt_arg then
      return M.opts.default_prompt
    end

    return assert(M.opts.prompts[prompt_arg], "Prompt '" .. prompt_arg .. "' wasn't found")
  end

  local prompt = get_prompt()

  local success, result = pcall(prompt.provider.request_completion_stream, prompt_segment.prompt, {
    on_partial = vim.schedule_wrap(function(partial)
      seg.add(partial)
    end),

    on_finish = vim.schedule_wrap(function(_, reason)
      if reason == 'stop' then
        seg.close()
      else
        seg.highlight("Error")
      end
    end),

    on_error = function(data, label)
      vim.notify(vim.inspect(data), vim.log.levels.ERROR, {title = 'stream error ' .. label})
    end
  }, nil, prompt.builder)

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
      local items = vim.tbl_keys(opts.prompts)

      if #arglead == 0 then return items end

      return vim.fn.matchfuzzy(items, arglead)
    end
  })
end

function M.setup(opts)
  local _opts = {
    responding_hl_group = "Comment",
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

