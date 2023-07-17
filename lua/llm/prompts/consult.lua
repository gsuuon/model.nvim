local util = require('llm.util')
local async = require('llm.util.async')

local provider = require('llm.provider')
local openai = require('llm.providers.openai')

local M = {}

function M.gpt_relevant_openapi_schema_path(schema, task, callback)
  async(function(wait, resolve)
    local gpt_prompt =
      'This api is:\n' .. schema.description
      .. '\n\nThese are the routes:\n'
      .. vim.json.encode(schema.routes)
      .. '\n\nWhich one would be useful in this task:\n'
      .. task
      .. '\n\nRespond with a json object of the path and method. Respond only with valid json, do not include an explanation e.g.:\n'
      .. [[`{ "path": "/somepath", "method": "post" }`]]

    local gpt_consistent = vim.tbl_extend('force', openai.default_prompt, {
      params = {
        temperature = 0.0,
        model = "gpt-3.5-turbo-0613"
      }
    })

    util.show(gpt_prompt, 'asking gpt')

    local gpt_response = wait(provider.complete(gpt_consistent, gpt_prompt, {}, resolve))

    if not gpt_response.success then error(gpt_response.error) end

    local route, err = util.json.decode(gpt_response.content)

    if route == nil then
      util.eshow('Failed to parse gpt response as json:\n' .. gpt_response.content)
      util.eshow(err)
      error('Unexpected gpt response')
    end

    if route.path == nil or route.method == nil then
      util.eshow('Gpt response unexpected')
      util.eshow(gpt_prompt)
      error('Unexpected gpt response')
    end

    local node =
      assert(
        assert(
          schema.schema.paths[route.path],
          'schema missing path ' .. route.path
        )[route.method],
        'path missing method ' .. route.method
      )

    return {
      schema = schema,
      relevant_route = {
        [route.path] = {
          [route.method] = node
        }
      }
    }
  end, callback)
end

return M
