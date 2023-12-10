local segment = require('model.util.segment')

local M = {}

function M.scroll(text, rate, set)
  local run = true

  local function scroll_(t)
    vim.defer_fn(function ()
      if run then
        local head = t:sub(1, 1)
        local tail = t:sub(2, #t)
        local text_ = tail .. head

        set('<' .. text_ .. '>')

        return scroll_(text_)
      end
    end, rate)
  end

  scroll_(text)

  return function()
    set('')
    run = false
  end
end

--- @param text string The text to display either as a marquee or notification.
--- @param seg? Segment segment to place the marquee after
--- @param hl? string Optional highlight group for the marquee segment. Defaults to 'Comment'.
--- @return function stop stop and clear the marquee
function M.handler_marquee_or_notify(text, seg, hl)
  if seg then
    local handler_seg = seg.details()
    local pending = segment.create_segment_at(
      handler_seg.details.end_row,
      handler_seg.details.end_col,
      hl or 'Comment'
    )
    return M.scroll(text .. '   ', 160, pending.set_virt)
  else
    vim.notify(text)
  end

  return function() end
end

return M
