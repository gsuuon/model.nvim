local segment = require("llm.segment")
local util = require("llm.util")

local M = {}

function M.setup(opts)
  opts = opts or {}

  M.provider = opts.provider or require("llm.providers.openai")
  M.provider.authenticate()
end

function M.request_completion_stream()

  -- should only do this if we're in visual mode
  local selection = util.cursor.selection()
  local text = util.buf.text(selection)

  local seg = segment.create_segment_at(
    selection.stop.row,
    selection.stop.col,
    "Comment"
  )

  M.provider.request_completion_stream(text,

    vim.schedule_wrap(function(partial)
      seg.add(partial)
    end),

    vim.schedule_wrap(function(_final, reason)
      if reason == 'stop' then
        seg.close()
      else
        seg.highlight("Error")
      end
    end)
  )
end

return M

