local M = {}

---@param client vim.lsp.Client
local function can_pull_diagnostics(client)
  return client.supports_method('textDocument/diagnostic')
end

---@param bufnr integer
local function pull_diagnostics(bufnr, callback)
  vim.lsp.buf_request(bufnr, 'textDocument/diagnostic', {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
  }, function(err, result, context, config)
    callback(err, result, context, config)
  end)
end

local function start_lsp_servers(bufnr)
  local ok, lsp_util = pcall(require, 'lspconfig.util')

  if not ok then
    return 0
  end

  local count = 0

  vim.api.nvim_buf_call(bufnr, function()
    local matching_configs = lsp_util.get_config_by_ft(vim.bo.filetype)
    for _, config in ipairs(matching_configs) do
      config.launch()
      count = count + 1
    end
  end)

  return count
end

function M.get_diagnostics_for_file(filename, callback)
  local bufnr = vim.fn.bufadd(filename)

  if bufnr == 0 then
    util.eshow('Failed to bufadd')
    error('Failed to bufadd: ' .. filename)
  end

  local was_loaded = vim.fn.bufloaded(bufnr) == 1
  vim.fn.bufload(bufnr)

  local started_servers = start_lsp_servers(bufnr)
  if started_servers == 0 then
    callback(nil)
    return
  end

  local diagnostics_listener = nil
  local timeout = nil

  local function cleanup()
    if diagnostics_listener then
      vim.api.nvim_del_autocmd(diagnostics_listener)
    end
    if timeout then
      timeout:stop()
    end
    if not was_loaded then
      vim.api.nvim_buf_delete(bufnr, { force = true, unload = true })
    end
  end

  local function handle_diagnostics()
    local diagnostics = vim.diagnostic.get(bufnr)
    if #diagnostics > 0 then
      cleanup()
      callback(diagnostics)
    end
  end

  local function try_pull_diagnostics()
    local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
    for _, client in ipairs(clients) do
      if can_pull_diagnostics(client) then
        pull_diagnostics(bufnr, function(err, _, _, _)
          if not err then
            vim.schedule(handle_diagnostics)
          end
        end)
        return true
      end
    end
    return false
  end

  -- Check for existing diagnostics first
  local existing_diags = vim.diagnostic.get(bufnr)
  if #existing_diags > 0 then
    cleanup()
    callback(existing_diags)
    return
  end

  -- Try to pull diagnostics if supported
  if try_pull_diagnostics() then
    timeout = vim.defer_fn(function()
      cleanup()
      callback(nil)
    end, 10000)
    return
  end

  -- Fall back to waiting for DiagnosticChanged
  diagnostics_listener = vim.api.nvim_create_autocmd('DiagnosticChanged', {
    buffer = bufnr,
    callback = handle_diagnostics,
  })

  timeout = vim.defer_fn(function()
    cleanup()
    callback(nil)
  end, 10000)
end

return M
