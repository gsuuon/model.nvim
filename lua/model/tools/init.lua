---@class Tool
---@field description string
---@field parameters table
---@field invoke fun(args: table, callback: fun(result: string)): string | fun(): nil takes args and optionally a callback, returns a string result or a cancel function. If cancel function is returned, the callback must be called to resolve the tool use

---@type table<string, Tool>
return {
  fetch_website = require('model.tools.fetch_website'),
  read_file = require('model.tools.read_file'),
  list_files = require('model.tools.list_files'),
  create_file = require('model.tools.create_file'),
  rewrite_file = require('model.tools.rewrite_file'),
  search_pattern = require('model.tools.search_pattern'),
  list_buffers = require('model.tools.list_buffers'),
  get_buffer_contents = require('model.tools.get_buffer_contents'),
  git = require('model.tools.git'),
  hand_over = require('model.tools.hand_over'),
}
