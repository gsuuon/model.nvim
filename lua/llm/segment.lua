local util = require('llm.util')

local M = {}

local segments_cache = {}

function M.ns_id()
  if M._ns_id == nil then
    M._ns_id = vim.api.nvim_create_namespace('llm.nvim')
  end

  return M._ns_id
end

local function end_delta(lines, origin_row, origin_col)
  local rows_added = #lines - 1
  local last_line_count = #lines[#lines]

  local new_col =
    rows_added > 0 and last_line_count or origin_col + last_line_count

  return {
    row = origin_row + rows_added,
    col = new_col
  }
end

local function create_segment_at(row, col, hl_group)

  local _ext_id = vim.api.nvim_buf_set_extmark(
    0,
    M.ns_id(),
    row,
    col,
    {
      hl_group = hl_group,

      -- these need to be set or else get_details doesn't return end_*s
      end_row = row,
      end_col = col
    }
  )

  local function get_details()
    if _ext_id == nil then
      util.error('Extmark for segment no longer exists')
    end

    local extmark = vim.api.nvim_buf_get_extmark_by_id(
      0,
      M.ns_id(),
      _ext_id,
      { details = true }
    )

    return {
      row = extmark[1],
      col = extmark[2],
      details = extmark[3]
    }
  end

  local _hl_group = hl_group
  local _data = {}

  return {

    add = vim.schedule_wrap(function(text)
      local lines = util.string.split_char(text, '\n')

      if lines == nil or #lines == 0 then return end

      local mark = get_details()

      local r = mark.details.end_row
      local c = mark.details.end_col

      vim.api.nvim_buf_set_text(0, r, c, r, c, lines)

      local end_pos = end_delta(lines, r, c)

      vim.api.nvim_buf_set_extmark(0, M.ns_id(), mark.row, mark.col, {
        id = _ext_id,
        end_col = end_pos.col,
        end_row = end_pos.row,
        hl_group = _hl_group -- need to set hl_group every time we want to update the extmark
      })
    end),

    highlight = vim.schedule_wrap(function(hl) -- this seems to be additive only
      _hl_group = hl

      local mark = get_details()

      mark.details.hl_group = _hl_group
      mark.details.id = _ext_id

      vim.api.nvim_buf_set_extmark(0, M.ns_id(), mark.row, mark.col, mark.details)
    end),

    clear_hl = vim.schedule_wrap(function()
      local mark = get_details()

      mark.details.hl_group = nil
      mark.details.id = _ext_id

      vim.api.nvim_buf_set_extmark(0, M.ns_id(), mark.row, mark.col, mark.details)
    end),

    delete = vim.schedule_wrap(function()
      local mark = get_details()

      local replacement = _data.original or {}

      vim.api.nvim_buf_set_text(
        0,
        mark.row,
        mark.col,
        mark.details.end_row,
        mark.details.end_col,
        replacement
      )
    end),

    ext_id = _ext_id,

    data = _data

  }
end

function M.create_segment_at(row, col, hl_group)
  local function shift_if_complete_line(pos)
    if pos.col == util.COL_ENTIRE_LINE then
      return {
        col = 0,
        row = pos.row + 1
      }
    end

    return pos
  end

  local function shift_to_bounds(pos)
    local buf_lines_count = vim.api.nvim_buf_line_count(0)
    local row_out_of_bounds = pos.row >= buf_lines_count

    if row_out_of_bounds then
      vim.api.nvim_buf_set_lines(0, -1, -1, false, {''})

      return {
        row = buf_lines_count,
        col = 0
      }
    else
      local row_length = #vim.api.nvim_buf_get_lines(0, pos.row, pos.row + 1, false)[1]

      local col_out_of_bounds = pos.col > row_length

      if col_out_of_bounds then
        return {
          row = pos.row,
          col = row_length - 1
        }
      end
    end

    return pos
  end

  local target_pos = shift_to_bounds(shift_if_complete_line({
    row = row,
    col = col
  }))

  local segment = create_segment_at(target_pos.row, target_pos.col, hl_group)

  segments_cache[segment.ext_id] = segment

  return segment
end

function M.query(pos)
  local extmark_details = vim.api.nvim_buf_get_extmarks(0, M.ns_id(), 0, -1, {details = true})

  local matches = {}

  -- Tried doing this differently but vim.tbl_flatten was acting weird
  -- also, debugging deep composition is difficult with lua

  for _, mark in ipairs(extmark_details) do
    local start = {
      row = mark[2],
      col = mark[3]
    }

    local details = mark[4]

    local final = {
      row = details.end_row,
      col = details.end_col
    }

    if util.position.is_bounded(pos, start, final) then
      local ext_id = mark[1]

      local seg = segments_cache[ext_id]

      if seg ~= nil then
        table.insert(matches, seg)
      end
    end
  end

  return matches
end

---@enum SegmentMode
M.mode = {
  APPEND = "append",
  REPLACE = "replace",
  -- BUFFER = "buffer"
}

M._debug = {}

function M._debug.extmarks()
  return vim.api.nvim_buf_get_extmarks(0, M.ns_id(), 0, -1, {})
end

return M
