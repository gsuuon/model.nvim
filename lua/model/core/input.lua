local util = require('model.util')

local M = {}

---@class Source
---@field selection? Selection
---@field lines string[]
---@field position Position

---@class Context
---@field before string Text before the selection or cursor
---@field after string Text after the selection or cursor
---@field filename string Selection buffer filename
---@field args string Additional command argument
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
  return {
    before = util.buf.text({
      start = {
        row = 0,
        col = 0,
      },
      stop = source.selection ~= nil and source.selection.start
        or source.position,
    }),
    after = util.buf.text({
      start = source.selection ~= nil and source.selection.stop
        or source.position,
      stop = {
        row = -1,
        col = -1,
      },
    }),
  }
end

---@param source Source
---@param args string
---@return InputContext
function M.get_input_context(source, args)
  local before_after = get_before_after(source)

  return {
    input = table.concat(source.lines, '\n'),
    context = {
      selection = source.selection,
      filename = util.buf.filename(),
      before = before_after.before,
      after = before_after.after,
      args = args,
    },
  }
end

return M
