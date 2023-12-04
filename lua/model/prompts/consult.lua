local util = require('model.util')

local provider = require('model.core.provider')
local openai = require('model.providers.openai')

local M = {}

function M.gpt_relevant_openapi_schema_path(schema, task, callback)
  local gpt_prompt =
      'This api is:\n' .. schema.description
      .. '\n\nThese are the routes:\n'
      .. vim.json.encode(schema.routes)
      .. '\n\nWhich one would be useful in this task:\n'
      .. task
      ..
      '\n\nRespond with a json object containing the path and method. Respond only with valid json, do not include an explanation. For example:\n'
      .. [[`{ "path": "/somepath", "method": "post" }`]]

  local gpt_consistent = vim.tbl_extend('force', openai.default_prompt, {
    params = {
      temperature = 0.0,
      model = "gpt-3.5-turbo-0613"
    }
  })

  provider.complete(gpt_consistent, { input = gpt_prompt }, function(gpt_response)
    local route, err = util.json.decode(gpt_response)

    if route == nil then
      util.eshow(gpt_response, 'Failed to parse as json')
      error(err)
    end

    if route.path == nil or route.method == nil then
      util.eshow(gpt_response, 'Unexpected response')
      error('gpt response missing required fields')
    end

    local node =
        assert(
          assert(
            schema.schema.paths[route.path],
            'schema missing path ' .. route.path
          )[route.method],
          'path missing method ' .. route.method
        )

    callback({
      schema = schema,
      relevant_route = {
        [route.path] = {
          [route.method] = node
        }
      }
    })
  end)
end

return M
