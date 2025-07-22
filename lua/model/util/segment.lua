local util = require('model.util')

---@class Segment
---@field add fun(text: string)
---@field add_line fun(line:string) add some text, ensuring it's own it's own line
---@field add_virt fun(text: string)
---@field set_text fun(text: string)
---@field get_text fun(): string
---@field set_virt fun(text: string, hl_group?:string, opts?: vim.api.keyset.set_extmark, on_error?: fun(err: any))
---@field clear_hl fun()
---@field delete fun()
---@field data table
---@field get_span fun(): Span
---@field highlight fun(hl_group: string)
---@field ext_id number

local M = {
  default_hl = 'Comment',
  join_undo = true, --- Join undos when adding and setting segment text
}

local segments_cache = {}
local undo_handlers_by_buf = {}

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
  ---@type string | nil
  local _hl_group = hl_group or M.default_hl
  local _data = {}
  local _did_add_text_to_undo = false
  local _did_delete = false
  local _text = ''

  local _ext_id
  do
    local last_line = vim.api.nvim_buf_line_count(bufnr) - 1
    local safe_row = math.min(row, last_line)
    local end_row = math.min(safe_row, last_line)

    _ext_id = vim.api.nvim_buf_set_extmark(bufnr, M.ns_id(), safe_row, col, {
      hl_group = hl_group,

      -- these need to be set or else get_details doesn't return end_*s
      end_row = end_row,
      end_col = col,
    })
  end

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

  ---@param span Span
  ---@param opts? vim.api.keyset.set_extmark
  local function _update_extmark(span, opts)
    local details = get_details()

    vim.api.nvim_buf_set_extmark(
      bufnr,
      M.ns_id(),
      span.start.row,
      span.start.col,
      vim.tbl_extend('force', details.details, {
        id = _ext_id,
        end_col = span.stop.col,
        end_row = span.stop.row,
      }, opts or {})
    )
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

  local function set_virt_text(text, virt_hl_group, opts)
    _update_extmark(
      get_span(),
      vim.tbl_deep_extend('force', {
        virt_text = { { text, virt_hl_group or 'Comment' } },
        virt_text_pos = 'inline',
      }, opts or {})
    )
  end

  local segment = {
    set_text = vim.schedule_wrap(function(text)
      if text == nil then
        return
      end

      local lines = vim.split(text, '\n')
      local span = get_span()

      if _did_add_text_to_undo and join_undo then
        pcall(vim.cmd.undojoin)
      end

      -- TODO FIXME can end_row be before row? no docs on the details dict
      vim.api.nvim_buf_set_text(
        bufnr,
        span.start.row,
        span.start.col,
        span.stop.row,
        span.stop.col,
        lines
      )

      _update_extmark({
        start = span.start,
        stop = end_delta(lines, span.start.row, span.start.col),
      })

      _text = text
    end),

    get_text = function()
      return _text
    end,

    set_virt = vim.schedule_wrap(function(text, virt_hl_group, opts, on_error)
      local ok, res = pcall(set_virt_text, text, virt_hl_group, opts)
      if not ok and on_error then
        on_error(res)
      end
    end),

    add = vim.schedule_wrap(function(text)
      local lines = vim.split(text, '\n')

      if lines == nil or #lines == 0 then
        return
      end

      local span = get_span()

      local r = span.stop.row
      local c = span.stop.col

      if _did_add_text_to_undo and join_undo then
        pcall(vim.cmd.undojoin) -- Errors if user did undo immediately before
        -- e.g. during a stream
      end

      vim.api.nvim_buf_set_text(bufnr, r, c, r, c, lines)

      _update_extmark({
        start = span.start,
        stop = end_delta(lines, r, c),
      })

      _text = _text .. text
      _did_add_text_to_undo = true
    end),

    add_line = vim.schedule_wrap(function(line)
      local span = get_span()

      if _did_add_text_to_undo and join_undo then
        pcall(vim.cmd.undojoin) -- Errors if user did undo immediately before
        -- e.g. during a stream
      end

      local last_next_lines = vim.api.nvim_buf_get_lines(
        bufnr,
        span.stop.row,
        span.stop.row + 2,
        false
      )

      local last_line = last_next_lines[1]
      local next_line = last_next_lines[2]

      local lines = { line }
      local lines_added = 1

      if last_line ~= '' then
        lines_added = lines_added + 1
        table.insert(lines, 1, '')
      end

      if next_line ~= '' then
        table.insert(lines, '')
      end

      vim.api.nvim_buf_set_text(
        bufnr,
        span.stop.row,
        span.stop.col,
        span.stop.row,
        span.stop.col,
        lines
      )

      _update_extmark({
        start = span.start,
        stop = {
          row = span.stop.row + lines_added,
          col = 0,
        },
      })

      _text = _text .. '\n' .. line .. '\n'
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
      if _did_delete then
        return
      end

      local span = get_span()

      vim.api.nvim_buf_set_text(
        bufnr,
        span.start.row,
        span.start.col,
        span.stop.row,
        span.stop.col,
        _data.original or {}
      )

      if not vim.api.nvim_buf_del_extmark(bufnr, M.ns_id(), _ext_id) then
        util.eshow('Tried to delete non-existing extmark')
      end

      segments_cache[_ext_id] = nil
      _did_delete = true
    end),

    ext_id = _ext_id,

    details = get_details,

    get_span = get_span,

    data = _data,
  }

  segment.bufnr = bufnr

  -- Setup undo handler if not already set for this buffer
  if not undo_handlers_by_buf[bufnr] then
    undo_handlers_by_buf[bufnr] = true

    -- Only override 'u' if it's not already mapped
    if vim.fn.maparg('u', 'n') == '' then
      vim.keymap.set('n', 'u', function()
        vim.cmd('undo') -- Perform normal undo first
        M.on_undo(bufnr) -- Then run our custom undo handler
      end, { buffer = bufnr })
    end
  end

  return segment
end

--- Handle undo event for a buffer
---@param bufnr number
function M.on_undo(bufnr)
  vim.schedule(function()
    -- Check all segments in this buffer
    for ext_id, seg in pairs(segments_cache) do
      if
        seg.bufnr == bufnr
        and not seg._did_delete
        and seg.data.original ~= nil
      then
        local span = seg.get_span()
        local ok, current_lines = pcall(
          vim.api.nvim_buf_get_text,
          bufnr,
          span.start.row,
          span.start.col,
          span.stop.row,
          span.stop.col,
          {}
        )

        if ok then
          local current_text = table.concat(current_lines, '\n')
          local original_text = table.concat(seg.data.original, '\n')

          if current_text == original_text then
            seg.delete()
          end
        else
          -- Segment is invalid (likely outside buffer range)
          seg.delete()
        end
      end
    end
  end)
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
