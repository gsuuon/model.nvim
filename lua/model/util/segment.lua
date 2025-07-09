local util = require('model.util')

---@class Segment
---@field add fun(text: string): nil
---@field add_virt fun(text: string): nil
---@field set_text fun(text: string): nil
---@field get_text fun(): string
---@field set_virt fun(text: string): nil
---@field clear_hl fun(): nil
---@field delete fun(): nil
---@field data table
---@field get_span fun(): Span
---@field highlight fun(hl_group: string): nil
---@field details fun(): {row: number, col: number, details: table, bufnr: number}

local M = {
  default_hl = 'Comment',
  join_undo = true, --- Join undos when adding and setting segment text
}

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

  local new_col = rows_added > 0 and last_line_count
    or origin_col + last_line_count

  return {
    row = origin_row + rows_added,
    col = new_col,
  }
end

---Create a new segment
---@param row number 0-indexed start row
---@param col number 0-indexed end row
---@param bufnr number
---@param hl_group? string
---@param join_undo? boolean Join set_text call undos. Will join any undos made between add and set_text.
---@return Segment
local function create_segment_at(row, col, bufnr, hl_group, join_undo)
  local _hl_group = hl_group or M.default_hl
  local _data = {}
  local _did_add_text_to_undo = false
  local _text = ''

  local _ext_id = vim.api.nvim_buf_set_extmark(bufnr, M.ns_id(), row, col, {
    hl_group = hl_group,

    -- these need to be set or else get_details doesn't return end_*s
    end_row = row,
    end_col = col,
  })

  local function get_details()
    if _ext_id == nil then
      error('Extmark for segment no longer exists')
    end

    local extmark = vim.api.nvim_buf_get_extmark_by_id(
      bufnr,
      M.ns_id(),
      _ext_id,
      { details = true }
    )

    -- remove ns_id, even though neovim returns it when setting the extmark it's
    -- an unexpected key
    local details = extmark[3]
    if details then
      details['ns_id'] = nil
    end

    return {
      row = extmark[1],
      col = extmark[2],
      details = details,
      bufnr = bufnr,
    }
  end

  local virt_text = ''

  local function set_virt_text(text)
    -- virtual text can't be multiline and doesn't wrap
    -- this workaround will set the first line of the virt text at the mark
    -- the other lines will start at the row under
    -- this can be weird in some cases. If the virt text is intended to replace
    -- a bit of inline text, e.g. foo<virt>baz -- in a multiline case the first
    -- line goes at <virt> while the rest will start the line under, leaving the baz.
    local mark = get_details()
    virt_text = text

    local virt_lines = vim.tbl_map(function(line)
      return { { line, _hl_group } }
    end, vim.split(virt_text, '\n'))

    local t = table.remove(virt_lines, 1)

    vim.api.nvim_buf_set_extmark(bufnr, M.ns_id(), mark.row, mark.col, {
      id = _ext_id,
      hl_group = _hl_group,
      virt_text = t,
      virt_text_pos = 'overlay',
      virt_lines = #virt_lines > 0 and virt_lines or nil,
    })
  end

  local function get_span()
    local deets = get_details()

    local end_row = deets.details.end_row or deets.row
    local end_col = deets.details.end_col or deets.col
    local start_row = math.min(deets.row, end_row)
    local start_col = math.min(deets.col, end_col)
    end_row = math.max(deets.row, end_row)
    end_col = math.max(deets.col, end_col)

    ---@type Span
    return {
      start = {
        row = start_row,
        col = start_col,
      },
      stop = {
        row = end_row,
        col = end_col,
      },
    }
  end

  return {

    set_text = vim.schedule_wrap(function(text)
      if text == nil then
        return
      end

      local lines = util.string.split_char(text, '\n')
      local mark = get_details()

      if _did_add_text_to_undo and join_undo then
        pcall(vim.cmd.undojoin)
      end

      -- TODO FIXME can end_row be before row? no docs on the details dict
      vim.api.nvim_buf_set_text(
        bufnr,
        mark.row,
        mark.col,
        mark.details.end_row or mark.row,
        mark.details.end_col or mark.col,
        lines
      )

      local end_pos = end_delta(lines, mark.row, mark.col)

      vim.api.nvim_buf_set_extmark(bufnr, M.ns_id(), mark.row, mark.col, {
        id = _ext_id,
        end_col = end_pos.col,
        end_row = end_pos.row,
        hl_group = _hl_group,
      })
      _text = text
    end),

    get_text = function()
      return _text
    end,

    set_virt = vim.schedule_wrap(set_virt_text),

    add_virt = vim.schedule_wrap(function(text)
      set_virt_text(virt_text .. text)
    end),

    add = vim.schedule_wrap(function(text)
      local lines = util.string.split_char(text, '\n')

      if lines == nil or #lines == 0 then
        return
      end

      local mark = get_details()

      local r = mark.details.end_row
      local c = mark.details.end_col

      if _did_add_text_to_undo and join_undo then
        pcall(vim.cmd.undojoin) -- Errors if user did undo immediately before
        -- e.g. during a stream
      end

      vim.api.nvim_buf_set_text(bufnr, r, c, r, c, lines)

      local end_pos = end_delta(lines, r, c)

      vim.api.nvim_buf_set_extmark(bufnr, M.ns_id(), mark.row, mark.col, {
        id = _ext_id,
        end_col = end_pos.col,
        end_row = end_pos.row,
        hl_group = _hl_group, -- need to set hl_group every time we want to update the extmark
      })

      _did_add_text_to_undo = true
    end),

    highlight = vim.schedule_wrap(
      function(hl) -- this seems to be additive only
        _hl_group = hl

        local mark = get_details()

        mark.details.hl_group = _hl_group
        mark.details.id = _ext_id

        vim.api.nvim_buf_set_extmark(
          bufnr,
          M.ns_id(),
          mark.row,
          mark.col,
          mark.details
        )
      end
    ),

    clear_hl = vim.schedule_wrap(function()
      local mark = get_details()

      _hl_group = nil
      mark.details.hl_group = nil
      mark.details.id = _ext_id

      vim.api.nvim_buf_set_extmark(
        bufnr,
        M.ns_id(),
        mark.row,
        mark.col,
        mark.details
      )
    end),

    delete = vim.schedule_wrap(function()
      local span = get_span()

      vim.api.nvim_buf_set_text(
        bufnr,
        span.start.row,
        span.start.col,
        span.stop.row,
        span.stop.col,
        _data.original or {}
      )

      vim.api.nvim_buf_del_extmark(bufnr, M.ns_id(), _ext_id)
    end),

    ext_id = _ext_id,

    details = get_details,

    get_span = get_span,

    data = _data,
  }
end

---@param row integer
---@param col integer
---@param hl_group? string
---@param bufnr? integer
function M.create_segment_at(row, col, hl_group, bufnr)
  if not bufnr or bufnr == 0 then
    -- Pin the buffer we use to the current buffer if bufnr is 0
    -- instead of always using the active one
    bufnr = vim.fn.bufnr('%')
  end

  ---@param pos Position
  local function get_row_length(pos)
    local line =
      vim.api.nvim_buf_get_lines(bufnr, pos.row, pos.row + 1, false)[1]

    return line == nil and 0 or #line, line ~= nil
  end

  local function shift_row_if_entire_unempty_line(pos)
    if pos.col == util.COL_ENTIRE_LINE then
      if get_row_length(pos) > 0 then
        -- add a row and return start of new row

        vim.api.nvim_buf_set_lines(
          bufnr,
          pos.row + 1,
          pos.row + 1,
          false,
          { '' }
        )

        return {
          col = 0,
          row = pos.row + 1,
        }
      else
        -- the row is empty, so we'll just use it

        return {
          col = 0,
          row = pos.row,
        }
      end
    end

    return pos
  end

  local function add_row_if_out_of_bounds(pos)
    local _, row_exists = get_row_length(pos)

    if not row_exists then
      vim.api.nvim_buf_set_lines(bufnr, pos.row, pos.row, false, { '' })
    end

    return pos
  end

  local function shift_col_to_line_bounds(pos)
    local row_length = get_row_length(pos)

    if pos.col > row_length then
      return {
        row = pos.row,
        col = row_length - 1,
      }
    end

    return pos
  end

  local target_pos = add_row_if_out_of_bounds(
    shift_col_to_line_bounds(
      shift_row_if_entire_unempty_line({ row = row, col = col })
    )
  )

  local segment = create_segment_at(
    target_pos.row,
    target_pos.col,
    bufnr,
    hl_group,
    M.join_undo
  )

  segments_cache[segment.ext_id] = segment

  return segment
end

--- Returns the most recent segment at the position
function M.query(pos)
  local extmark_details =
    vim.api.nvim_buf_get_extmarks(0, M.ns_id(), 0, -1, { details = true })

  -- iterate backwards so recent markers are higher
  for idx = #extmark_details, 1, -1 do
    local mark = extmark_details[idx]

    local start = {
      row = mark[2],
      col = mark[3],
    }

    local details = mark[4]

    local stop = {
      row = details.end_row or mark[2],
      col = details.end_col or util.COL_ENTIRE_LINE, -- takes the whole line
    }

    if util.position.is_bounded(pos, start, stop) then
      local ext_id = mark[1]

      local seg = segments_cache[ext_id]

      if seg ~= nil then
        return seg
      end
    end
  end
end

--- Finds all segments at position, most recent first
function M.query_all(pos)
  local extmark_details =
    vim.api.nvim_buf_get_extmarks(0, M.ns_id(), 0, -1, { details = true })

  ---@type Segment[]
  local results = {}

  -- iterate backwards so recent markers are higher
  for idx = #extmark_details, 1, -1 do
    local mark = extmark_details[idx]

    local start = {
      row = mark[2],
      col = mark[3],
    }

    local details = mark[4]

    local stop = {
      row = details.end_row or mark[2],
      col = details.end_col or util.COL_ENTIRE_LINE, -- takes the whole line
    }

    if util.position.is_bounded(pos, start, stop) then
      local ext_id = mark[1]

      local seg = segments_cache[ext_id]

      if seg ~= nil then
        table.insert(results, seg)
      end
    end
  end

  return results
end

M._debug = {}

function M._debug.extmarks()
  return vim.api.nvim_buf_get_extmarks(0, M.ns_id(), 0, -1, { details = true })
end

return M
