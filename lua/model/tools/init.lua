---@class Tool
---@field description string Description to provide the LLM. Include instructions and guidelines if necessary.
---@field parameters table JSON schema of the arguments the tool expects
---@field invoke fun(args: table, callback: fun(result: string)): cancel: fun(), message: string? Synchronously returns a string result or asynchronously calls the callback function, returning a function which cancels the task. Invoke is called when the last message in a Chat has tool_calls data section. If the tool has a presentation then invoke should collect the side-effects of the presentation instead of executing the tool itself. For example, a file editing tool should present the modified file in `tool.presentation` to the user. The user can then accept, edit, or reject the modification by diff hunk. The final saved file is then returned by invoke to be fed back to the LLM.
---@field presentation fun(): consumer: fun(partial: string) Presents the tool call to the user as it's streamed in. Returns a streaming partial json consumer. Presentation is called as soon as we receive any arguments for this tool, then the returned function is called for each tool argument partial.
---@field presentation_autoaccept fun(args: any, done: fun()) If autoaccept matches this tool call and the tool has a presentation, then presentation_autoaccept runs after the LLM response completes. Use this to take presentation side effects (e.g. to `:write` modified buffers presented to user).

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
  edit_file_treesitter = require('model.tools.edit_file_treesitter'),
  get_file_treesitter = require('model.tools.get_file_treesitter'),
}
