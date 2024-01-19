local u = require('model.store.util')

local M = {}

---@class FunctionItem
---@field content string
---@field filepath string
---@field name string

---@class Item
---@field content string
---@field id string
---@field meta? table

local function get_git_root()
  return vim.fn.systemlist('git rev-parse --show-toplevel')[1]
end

function M.load(opts, force)
  if M.store_did_init == true and not force then
    return
  end

  local store_root_dir = (opts or {}).store_root_dir or get_git_root()
  M.store_root_dir = store_root_dir

  vim.cmd([[
    py import json
    py import store
    py s = store.load_or_initialize_store(']] .. M.store_root_dir .. [[')
  ]])

  local store_items_count = vim.fn.pyeval("len(s['items'])")
  local store_location = vim.fn.pyeval("s['abs_path']")
  vim.notify(
    'Loaded '
      .. store_items_count
      .. ' items in store.json at '
      .. store_location
  )

  M.store_did_init = true
end

function M.get_known_ids()
  return vim.fn.pyeval("[ i['id'] for i in s['items'] ]")
end

---@return { id: string, content: string, similarity: number }[]
function M.query_store(prompt, count, similarity)
  if similarity == nil then
    return vim.fn.py3eval(
      [[store.query_store(]]
        .. u.escape_quotes(prompt)
        .. [[, ]]
        .. count
        .. [[, s)]]
    )
  else
    local filter = [[lambda item, similarity: similarity > ]] .. similarity

    return vim.fn.py3eval(
      [[store.query_store(]]
        .. u.escape_quotes(prompt)
        .. [[, ]]
        .. count
        .. [[, s, filter=]]
        .. filter
        .. [[)]]
    )
  end
end

local ts_source = require('model.store.sources.treesitter')

---@param function_item FunctionItem
local function normalize_function_item_filepath_to_store(function_item)
  local store_rel_path = vim.fn.pyeval(
    'store.path_relative_to_store(r"' .. function_item.filepath .. '", s)'
  )

  return {
    id = store_rel_path .. ':' .. function_item.name,
    content = function_item.content,
  }
end

--- Add items to the git-local vector store. Expects store to be initialized.
--- Item content will be embedded with openai ada. Items that match existing id and content
--- won't be embedded again.
---@param items Item[] items
function M.add_items(items)
  vim.cmd([[py store.update_store_and_save(]] .. u.to_python(items) .. [[,s)]])
end

function M.add_files(root_path)
  vim.cmd(
    [[py store.update_with_files_and_save(s, files_root=']]
      .. root_path
      .. [[')]]
  )
end

function M.add_lua_functions(glob)
  if glob == nil then
    glob = vim.fn.expand('%')
  end
  -- Extracts lua functions as items
  local function to_lua_functions(file)
    return vim.tbl_map(
      normalize_function_item_filepath_to_store,
      ts_source.lang.lua.functions(file)
    )
  end

  ---@param glob string glob pattern to search for files, starting from current directory
  ---@param to_items function converts each filepath to a list of items
  local function glob_to_items(glob, to_items)
    local filepaths = vim.fn.glob(glob, nil, true)

    local results = {}

    for _, filepath in ipairs(filepaths) do
      -- show(filepath)
      local file = ts_source.ingest_file(filepath)
      local items = to_items(file)

      for _, item in ipairs(items) do
        table.insert(results, item)
      end
    end

    return results
  end

  M.add_items(glob_to_items(glob, to_lua_functions))
end

M.prompt = {}

function M.prompt.query_store(input, count, similarity)
  M.load()

  local context_results = M.query_store(input, count, similarity)

  local context = table.concat(
    vim.tbl_map(function(x)
      return '```' .. x.id .. '\n' .. x.content .. '\n```'
    end, context_results),
    '\n'
  )

  return context
end

return M
