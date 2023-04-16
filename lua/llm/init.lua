local segment = require("llm.segment")
local util = require("llm.util")

local M = {}

function M._get_prompt_and_segment()

  -- visual mode
  local selection = util.cursor.selection()
  local text = util.buf.text(selection)

  local seg = segment.create_segment_at(
    selection.stop.row,
    selection.stop.col,
    "Comment"
  )

  return {
    prompt = text,
    segment = seg
  }
end

---@class StreamHandlers
---@field on_partial (fun(partial_text: string): nil)
---@field on_finish (fun(complete_text: string, finish_reason: string): nil)
---@field on_error (fun(data: any, label: string): nil) }

function M.request_completion_stream()

  local prompt_segment = M._get_prompt_and_segment()
  local seg = prompt_segment.segment

  M.provider.request_completion_stream(prompt_segment.prompt, {

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
  })
end

function M.commands(opts)
  vim.api.nvim_create_user_command("Llm", M.request_completion_stream, {
    range = true,
    desc = "Request completion of selection",
    force = true
    -- TODO add custom Llm transform functions to complete :command-complete
    -- complete = function() end
  })
end

function M.setup(opts)
  opts = opts or {}

  M.provider = opts.provider or require("llm.providers.openai")
  M.provider.authenticate()

  M.commands(opts)
end

return M

