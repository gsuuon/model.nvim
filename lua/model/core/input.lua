local util = require('model.util')

local M = {}

---@class Source
---@field selection? Selection
---@field lines string[]
---@field position Position

---@class Context
---@field before string Text before the selection or cursor
---@field after string Text after the selection or cursor
---@field before_range Span Before range
---@field after_range Span After range
---@field filename string Selection buffer filename
---@field args string Additional command argument
---@field position Position Position of cursor
---@field selection? Selection Selection if given

---@class InputContext
---@field input string
---@field context Context

function M.get_source(want_visual_selection)
  if want_visual_selection then
    local selection = util.cursor.selection()
    local lines = util.buf.text(selection)

    return {
      selection = selection,
      position = util.cursor.position(),
      lines = lines,
    }
  else
    return {
      position = util.cursor.position(),
      lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
    }
  end
end

local function get_before_after(source)
  local before_range = {
    start = {
      row = 0,
      col = 0,
    },
    stop = source.selection ~= nil and source.selection.start
      or source.position,
  }

  local after_range = {
    start = source.selection ~= nil and source.selection.stop
      or source.position,
    stop = {
      row = -1,
      col = -1,
    },
  }

  local after = util.buf.text(after_range)

  return {
    before = util.buf.text(before_range),
    after = after,
    before_range = before_range,
    after_range = {
      start = after_range.start,
      stop = {
        row = after_range.start.row + #after,
        col = #after[#after],
      },
    },
  }
end

---@param source Source
---@param args string
function M.get_input_context(source, args)
  local before_after = get_before_after(source)

  ---@type InputContext
  return {
    input = table.concat(source.lines, '\n'),
    context = {
      selection = source.selection,
      filename = util.buf.filename(),
      position = source.position,
      before = table.concat(before_after.before, '\n'),
      after = table.concat(before_after.after, '\n'),
      before_range = before_after.before_range,
      after_range = before_after.after_range,
      args = args,
    },
  }
end

return M
