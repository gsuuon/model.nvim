local util = require("llm.util")

local M = {}

function M.ns_id()
  if M._ns_id == nil then
    M._ns_id = vim.api.nvim_create_namespace('llm.nvim')
  end

  return M._ns_id
end

function M._get_extmark_details(mark_id)
  return table.unpack(vim.api.nvim_buf_get_extmark_by_id(0, M.ns_id(), mark_id, { details = true }))
end

function M._end_diff(lines, origin_row, origin_col)
  local rows_added = #lines - 1
  local last_line_count = #lines[#lines]

  local new_col =
    rows_added > 0 and last_line_count or origin_col + last_line_count

  return table.unpack { origin_row + rows_added, new_col }
end

function M._create_segment_at(_row, _col, _hl_group)
  local open = function(row_start, col_start, row_end, col_end, hl_group)
    return vim.api.nvim_buf_set_extmark(
      0,
      M.ns_id(),
      row_start,
      col_start,
      {
        hl_group = hl_group,

        -- these need to be set or else get_details doesn't return end_*s
        end_row = row_end or row_start,
        end_col = col_end or col_start
      }
    )
  end

  local _extmark_id = open(_row, _col, _row, _col, _hl_group)

  local close = function()
    return vim.api.nvim_buf_del_extmark(0, M.ns_id(), _extmark_id)
  end

  return {
    add = function(text)
      local lines = util.string.split(text, '\n')

      if lines == nil then
        error("Tried to add nothing")
      end

      local row, col, details = M._get_extmark_details(_extmark_id)

      local r = details.end_row
      local c = details.end_col

      vim.api.nvim_buf_set_text(0, r, c, r, c, lines)

      local new_end_row, new_end_col = M._end_diff(lines, r, c)

      vim.api.nvim_buf_set_extmark(0, M.ns_id(), row, col, {
        id = _extmark_id,
        end_col = new_end_col,
        end_row = new_end_row,
        hl_group = _hl_group
      })
    end,

    highlight = function(hl_group)
      _hl_group = hl_group

      local row, col, details = M._get_extmark_details(_extmark_id)
      details.hl_group = _hl_group
      details.id = _extmark_id

      vim.api.nvim_buf_set_extmark(0, M.ns_id(), row, col, details)
    end,

    clear_hl = function()
      local row, col, details = M._get_extmark_details(_extmark_id)

      close()
      _hl_group = nil
      _extmark_id = open(row, col, details.end_row, details.end_col)
    end,

    close = close,

    delete = function()
      local row, col, details = M._get_extmark_details(_extmark_id)
      vim.api.nvim_buf_set_text(0, row, col, details.end_row, details.end_col, {})
    end,

  }
end

function M.create_segment_at(_row, _col, _hl_group)
  if _col == util.COL_ENTIRE_LINE then
    local target_row = _row + 1

    if target_row >= vim.api.nvim_buf_line_count(0) then
      vim.api.nvim_buf_set_lines(0, -1, -1, false, {""})
    end

    return M._create_segment_at(_row + 1, 0, _hl_group)
  else
    local row_length = #vim.api.nvim_buf_get_lines(0, _row, _row + 1, false)[1]

    return M._create_segment_at(_row, math.min(_col, row_length), _hl_group)
  end
end

M._debug = {}

function M._debug.extmarks()
  return vim.api.nvim_buf_get_extmarks(0, M.ns_id(), 0, -1, {})
end

return M
