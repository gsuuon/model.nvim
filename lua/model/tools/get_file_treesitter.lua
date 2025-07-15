local treesitter = require('model.util.treesitter')
local files = require('model.util.files')

return {
  description = [[
Get the top-level tree-sitter nodes of a file. Returns an array of nodes with their name, start line number, and what the first line contains.

If you read_file a file you may edit, it's useful to also get the treesitter nodes.

Documentation comment nodes often appear above element nodes they describe. Comments are _separate_ nodes from the element itself. The comments above a function may describe it. For example, consecutive lines of comment nodes with no blank space are often doc strings.
]],
  parameters = {
    type = 'object',
    properties = {
      path = {
        type = 'string',
        description = 'Path of the file to analyze.',
      },
    },
    required = { 'path' },
  },
  invoke = function(args)
    if type(args.path) ~= 'string' then
      error('Invalid path: must be a string')
    end

    -- First ensure the file is loaded, similar to read_file.lua
    if not files.is_file_within_cwd(args.path) then
      error(
        'File must exist and be within current working directory: ' .. args.path
      )
    end

    local nodes = treesitter.file_top_level_nodes(
      args.path,
      nil -- LLM may assume comments are part of function nodes if they're documentation
      -- { 'comment' } We might make this an argument but it's likely to just confuse the LLM
    )

    -- Format the nodes into a readable string
    local result = {}
    for _, node in ipairs(nodes) do
      table.insert(
        result,
        string.format('%s (line %d): %s', node.name, node.line, node.text)
      )
    end

    return table.concat(result, '\n')
  end,
}
