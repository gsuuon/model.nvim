local M = {}

--- Builds a string representing the directory structure of the given filepaths
function M.directory_structure(filepaths)
  -- Returns parent directories and filename given a filepath, e.g.
  -- assert(vim.deep_equal(get_path_parts('foo/bar/baz'), {
  --   parents = { 'foo', 'bar' },
  --   filename = 'baz'
  -- }))
  -- assert(vim.deep_equal(get_path_parts('baz'), { filename = 'baz' }))
  local function get_path_parts(filepath)
    local parts = {}
    for part in string.gmatch(filepath, '[^/]+') do
      table.insert(parts, part)
    end
    if #parts == 1 then
      return {
        parents = {},
        filename = parts[1],
      }
    else
      return {
        parents = vim.list_slice(parts, 1, #parts - 1),
        filename = parts[#parts]
      }
    end
  end

  -- Contains directory structure. Keys are files or directories. Values are a table if the key
  -- is a directory, or true if the key is a filename.
  -- directory = { foo = { bar = { 'baz' }, quix = true, ['README.md'] = true }
  local directory = {}

  for _, filepath in ipairs(filepaths) do
    local path = get_path_parts(filepath)
    local current_directory = directory

    for _, parent in ipairs(path.parents) do
      if not current_directory[parent] then
        current_directory[parent] = {}
      end
      current_directory = current_directory[parent]
    end
    current_directory[path.filename] = true
  end

  local function draw_diagram(node, parents, current_tree)
    local current_tree_ = current_tree

    for path, item in pairs(node) do
      local indents = string.rep('  ', #parents)

      if type(item) == 'table' then
        local parents_ = vim.list_slice(parents)
        table.insert(parents_, path)

        current_tree_ = current_tree_ .. draw_diagram(
          item,
          parents_,
          indents .. path .. '/\n'
        )
      else
        current_tree_ = current_tree_ .. indents .. path .. '\n'
      end
    end

    return current_tree_
  end

  return draw_diagram(directory, {}, '')
end

function M.git_files(exclude_untracked)
  if exclude_untracked then
    return vim.fn.systemlist({'git', 'ls-files'})
  end

  return vim.fn.systemlist({'git', 'ls-files', '-co', '--exclude-standard'})
end

return M
