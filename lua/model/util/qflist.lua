local util = require('model.util')

local qfid = nil

local function get_or_create_qfid()
  if not qfid then
    local success = vim.fn.setqflist({}, ' ', { title = 'model.nvim context' })

    if success ~= 0 then
      util.eshow('failed to create qflist')
    end

    qfid =
      vim.fn.getqflist({ items = {}, title = 'model.nvim context', id = 0 }).id
  end
  return qfid
end

local function add(buf_or_filename)
  local filename = type(buf_or_filename) == 'number'
      and vim.fn.bufname(buf_or_filename)
    or buf_or_filename
    or vim.fn.bufname()
  local bufnr = type(buf_or_filename) == 'number' and buf_or_filename
    or vim.fn.bufnr(filename)

  local qf = vim.fn.getqflist({ id = get_or_create_qfid(), items = {} })

  local already_added = vim.tbl_contains(qf.items or {}, function(item)
    return vim.fn.bufname(item.bufnr) == filename
  end, { predicate = true })

  if not already_added then
    vim.fn.setqflist({}, 'a', {
      id = get_or_create_qfid(),
      items = {
        {
          filename = filename,
          text = 'model.nvim context',
          bufnr = bufnr,
        },
      },
    })
  end
end

local function remove(buf_or_filename)
  local filename = type(buf_or_filename) == 'number'
      and vim.fn.bufname(buf_or_filename)
    or buf_or_filename
    or vim.fn.bufname()
  local bufnr = type(buf_or_filename) == 'number' and buf_or_filename
    or vim.fn.bufnr(filename)

  vim.fn.setqflist(
    vim.tbl_filter(function(item)
      return item.bufnr ~= bufnr
    end, vim.fn.getqflist({ id = get_or_create_qfid() }).items or {}),
    'r',
    { id = get_or_create_qfid() }
  )
end

local function clear()
  vim.fn.setqflist({}, 'r', { id = get_or_create_qfid() })
end

local function get_text()
  local seen_files = {}
  return table.concat(
    vim.tbl_map(
      function(item)
        local filename = vim.fn.bufname(item.bufnr)

        if seen_files[filename] then
          return ''
        end
        seen_files[filename] = true

        local filetype = vim.bo[item.bufnr].filetype
        local file_content =
          vim.api.nvim_buf_get_lines(item.bufnr, 0, -1, false)

        if #file_content == 0 then
          file_content = assert(
            vim.fn.readfile(filename),
            'Failed to read file: ' .. filename
          )
        end

        return string.format(
          '%s\n```%s\n%s\n```\n\n',
          filename == '' and ''
            or string.format('File: `%s`', util.path.relative_norm(filename)),
          filetype,
          table.concat(file_content, '\n')
        )
      end,
      vim.fn.getqflist({ id = get_or_create_qfid(), items = {} }).items or {}
    )
  )
end

local function set_current()
  local nr = vim.fn.getqflist({ id = get_or_create_qfid(), nr = 0 }).nr
  vim.cmd(string.format('silent! %dchistory', nr))
end

local function import_current()
  local current_qf = vim.fn.getqflist()
  if #current_qf > 0 then
    vim.fn.setqflist({}, 'a', { id = get_or_create_qfid(), items = current_qf })
  end
end

return {
  add = add,
  remove = remove,
  clear = clear,
  get_text = get_text,
  set_current = set_current,
  import_current = import_current,
}
