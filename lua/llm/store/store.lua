local M = {}

---@class FunctionItem
---@field content string
---@field filepath string
---@field name string

local function get_git_root()
  return vim.fn.systemlist('git rev-parse --show-toplevel')[1]
end

function M.init(opts)
  local store_root_dir = (opts or {}).store_root_dir or get_git_root()
  M.store_root_dir = store_root_dir

  vim.cmd([[
    py import json
    py import store
    py s = store.load_or_initialize_store(']] .. M.store_root_dir .. [[')
  ]])
end

function M.store_get_known_ids()
  return vim.fn.pyeval("[ i['id'] for i in s['items'] ]")
end

function M.add_files(root_path)
  vim.cmd([[py store.update_with_files_and_save(s, files_root=']].. root_path .. [[')]])
end

function M.query_store(prompt, count, similarity)
  if similarity == nil then
    return vim.fn.py3eval(
      [[store.query_store(']] .. prompt .. [[', ]] .. count .. [[, s)]]
    )
  else
    local filter = [[lambda item, similarity: similarity > ]] .. similarity

    return vim.fn.py3eval(
      [[store.query_store(']] .. prompt .. [[', ]] .. count .. [[, s, filter=]] .. filter ..[[)]]
    )
  end
end

--- Assumes json has been imported in python repl
local function to_python(o)
  local as_json = vim.json.encode(o)
  if as_json == nil then
    error("failed to encode json")
  end
  local sanitized = [[r"""]] .. as_json:gsub([["""]], [[\"\"\"]]) .. [["""]]

  return [[json.loads(]] .. sanitized .. [[, strict=False)]]
end

function M.add_items(items)
  vim.cmd([[py store.update_store_and_save(]] .. to_python(items) .. [[,s)]])
end

local ts_source = require('llm.store.sources.treesitter')

---@param function_item FunctionItem
local function normalize_function_item_filepath_to_store(function_item)
  local store_rel_path = vim.fn.pyeval('store.path_relative_to_store(r"' .. function_item.filepath .. '", s)')

  return {
    id = store_rel_path .. ':' .. function_item.name,
    content = function_item.content
  }
end

local function to_lua_functions(file)
  return vim.tbl_map(normalize_function_item_filepath_to_store, ts_source.lang.lua.functions(file))
end

local function glob_to_items(glob, to_items)
  local filepaths = vim.fn.glob(glob,nil,true)

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

return M
