local util = require('llm.util')
local curl = require('llm.curl')
local async = require('llm.util.async')

local M = {}

function M.schema_descripts(url, cb)
  -- TODO extract component references
  async(function(wait, resolve)
    local schema = wait(curl.request({ url = url }, resolve, util.eshow))

    local parsed, err = util.json.decode(schema)
    if parsed == nil then
      util.eshow(schema, 'Failed to parse schema')
      error(err)
    end

    local paths = parsed.paths

    local routes = {}

    for route, route_node in pairs(paths) do
      for method, method_node in pairs(route_node) do
        table.insert(routes, {
          route = route,
          method = method,
          description = method_node.description
        })
      end
    end

    return {
      routes = routes,
      description = parsed.info.description,
      schema = parsed
    }
  end, cb)
end

function M.markdown_code(md_text)
  local function _extract_markdown_code(text)
    if not text:match('```') then
      return text
    end

    local blocks = util.string.extract_markdown_code_blocks(text)

    if #blocks == 0 then -- we may get a code block with no newlines between ```'s
      return text:match('^```(.+)```$')
    elseif #blocks == 1 then
      return blocks[1].code or blocks[1].text
    end

    local code_blocks = vim.tbl_filter(function(block)
      if block.text ~= nil then
        vim.notify(block.text)
      end
      return block.code ~= nil
    end, blocks)

    return table.concat(
      vim.tbl_map(function (block)
        return block.code
      end, code_blocks),
      '\n'
    )
  end

  local extracted = _extract_markdown_code(md_text)
  if extracted == '' then
    return md_text
  else
    return extracted
  end
end

return M
