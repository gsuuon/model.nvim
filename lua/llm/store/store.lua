local M = {}

local function get_git_root()
  return vim.fn.systemlist('git rev-parse --show-toplevel')[1]
end

function M.init(opts)
  local store_root_dir = (opts or {}).store_root_dir or get_git_root()
  M.store_root_dir = store_root_dir

  vim.cmd([[
    py import store
    py s = store.load_or_initialize_store(']] .. M.store_root_dir .. [[')
  ]])
end

function M.check_store()
  -- vim.cmd("py print(s)")
  -- vim.cmd("py print(s['abs_path'])")
  vim.cmd("py print([ i['id'] for i in s['items'] ])")
end

function M.add_files(root_path)
  vim.cmd([[py store.update_with_files_and_save(s, files_root=']].. root_path .. [[')]])
end

function M.query_store(prompt, count)
  local results = vim.fn.py3eval(
    [[store.query_store(']] .. prompt .. [[', ]] .. count .. [[, s)]]
  )

  return results
end

function M.add_items()
  local xs = {
    {
      id = 'someid',
      content = 'somecontent',
      meta = {
        type = 'file'
      }
    }
  }

  local xs_json = json_encode(xs)

  vim.cmd([[
    py store.add_items(json.loads(']] .. xs_json .. [['), s)
  ]])
end

-- M.init()
-- M.add_files('.')
-- M.check_store()
-- show(M.query_store([[add a segment mode that inserts text at cursor position]], 1))

return M
