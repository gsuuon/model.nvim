-- directory of the default tools
-- add new tools here to include as part of default set
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
}
