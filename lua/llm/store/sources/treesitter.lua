local ts_utils = require('nvim-treesitter.ts_utils')
local M = {}

---@class File
---@field filepath string
---@field content string

---@param file File
function M.ts_extract(file, extract_child)
  local lang = vim.treesitter.get_lang(vim.filetype.match({filename = file.filepath}))
  local parser = vim.treesitter.get_string_parser(file.content, lang)
  local tree = parser:parse()[1]
  local root = tree:root()

  local results = {}

  for child in root:iter_children() do
    local result = extract_child(child, file)
    if result ~= nil then
      table.insert(results, result)
    end
  end

  return results
end

local function node_get_text(node, content)
  local _,_,start = node:start()
  local _,_,end_ = node:end_()

  return content:sub(start + 1, end_)
end

function M.ts_extract_function(opts)
  local type = opts.type
  local get_name = opts.get_name

  return function (child, file)
    if child:type() == type then
      local store_rel_path = vim.fn.pyeval('store.path_relative_to_store("' .. file.filepath .. '", s)')

      return {
        content = node_get_text(child, file.content),
        id = store_rel_path .. ':' .. node_get_text(get_name(child), file.content)
      }
    end
  end
end

M.lang = {}
M.lang.lua = {}

function M.lang.lua.functions(file)
  return M.ts_extract(
    file,
    M.ts_extract_function({
      type = 'function_declaration',
      get_name =
        function(child)
          return child:field('name')[1]
        end
    })
  )
end

function M.ingest_file(filepath)
  local file = io.open(filepath, 'r')
  if file == nil then
    error('Unable to open file: ' .. filepath)
  end

  local content = file:read("*a")

  return {
    filepath = filepath,
    content = content
  }
end

-- (function()
--   local file = ingest_file('treesitter.lua')
--   show(M.lang.lua.functions(file))
-- end)()

return M
