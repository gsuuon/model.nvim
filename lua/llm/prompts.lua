local util = require('llm.util')

local M = {}

M.user = {}
M.plugin = {}

local function get_global_user()
  return M.user
end

local function get_global_plugin()
  return M.plugin
end

local function get_buffer_user(nr)
  return vim.b[nr or 0].llm_prompts_user or {}
end

local function get_buffer_plugin(nr)
  return vim.b[nr or 0].llm_prompts_plugin or {}
end

local function namespace_prompt_plugin(prompt, plugin)
  return prompt .. '@' .. plugin
end

local function plugin_prompt_names(plugin_prompts)
  local names = {}
  for plugin, prompts in pairs(plugin_prompts) do
    for prompt in pairs(prompts) do
      table.insert(names, namespace_prompt_plugin(prompt, plugin))
    end
  end
  return names
end

---Gets all prompt names available in the current buffer
---@return string[] names prompt names, plugins are namespaced
local function get_prompt_names()
  local global_user = {}
  for name in util.module.autopairs(get_global_user()) do
    table.insert(global_user, name)
  end

  -- FIXME these can shadow
  return vim.tbl_flatten({
    vim.tbl_keys(get_buffer_user()),
    global_user,
    plugin_prompt_names(get_buffer_plugin()),
    plugin_prompt_names(get_global_plugin()),
  })
end

local function match_plugin_prompt_name(prompt_name)
  local prompt, plugin = prompt_name:match('(.+)@(.+)')
  if prompt and plugin then
    return {
      prompt = prompt,
      plugin = plugin
    }
  end
end

function M.set_global_user_prompts(prompts)
  M.user = prompts
end

---Set plugin prompts globally
---@param name string plugin name
---@param prompts table<string, Prompt> prompts
function M.add_global_plugin_prompts(name, prompts)
  -- TODO probably want to track if something gets overwritten
  M.plugin = vim.tbl_extend('force', M.plugin, {[name] = prompts})
end

local function extend_buffer_var(name, value, bnr)
  bnr = bnr or 0
  local existing = vim.b[bnr][name]
  if existing ~= nil then
    vim.b[bnr][name] = vim.tbl_extend('force', existing, value)
  else
    vim.b[bnr][name] = value
  end
end

function M.set_buffer_user_prompts(prompts)
  extend_buffer_var('llm_prompts_user', prompts)
end

---Add plugin prompts to the buffer
---@param name string plugin name
---@param prompts table<string, Prompt> prompts
function M.add_buffer_plugin_prompts(name, prompts)
  extend_buffer_var('llm_prompts_plugin', {[name]= prompts})
end

---Returns the prompt given the name
---@param name string Name of the prompt, if provided by plugin it should be prompt_name@plugin_name
function M.get_prompt(name)
  local buffer_user = get_buffer_user()[name]
  if buffer_user then return buffer_user end

  local global_user = get_global_user()[name]
  if global_user then return global_user end

  local plug = match_plugin_prompt_name(name)
  if plug then
    local buffer_prompt = vim.tbl_get(
      get_buffer_plugin(),
      plug.plugin,
      plug.prompt
    )
    if buffer_prompt then return buffer_prompt end

    return vim.tbl_get(
      get_global_plugin(),
      plug.plugin,
      plug.prompt
    )
  end
end

function M.complete_arglead_prompt_names(arglead)
  local prompt_names = get_prompt_names()

  if #arglead == 0 then return prompt_names end
  return vim.fn.matchfuzzy(prompt_names, arglead)
end

local function test()
  -- M.set_global_user_prompts(util.module.autoload('llm.starter_prompts'))
  M.set_buffer_user_prompts({codego = 'code go'})
  M.set_buffer_user_prompts({boop = 'boop prompt'})
  M.add_buffer_plugin_prompts('baps', { bap = 'bap'})
  M.add_buffer_plugin_prompts('boops', { boop = 'boopsbooplocal'})
  -- M.add_global_plugin_prompts('baps', { bapppp = 'bapppp'})
  -- M.add_global_plugin_prompts('boops', { boop = 'boopsboopglobal'})
  -- what do I do about shadowing?

  -- show(get_prompt_names())
  -- show(M.get_prompt('bap@baps'))
  -- show(M.complete_arglead_prompt_names('code'))
end

return M
