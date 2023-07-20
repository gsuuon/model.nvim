local llm = require('llm')
local util = require('llm.util')
local curl = require('llm.curl')
local segment = require('llm.segment')
local openai = require('llm.providers.openai')
local palm = require('llm.providers.palm')
local huggingface = require('llm.providers.huggingface')
local kobold = require('llm.providers.kobold')

local provider = require('llm.provider')

local gpt = {
  provider = openai,
  builder = function(input)
    return {
      messages = {
        {
          role = 'user',
          content = input
        }
      }
    }
  end
}

local ada = {
  provider = openai,
  options = {
    endpoint = 'completions'
  },
  params = {
    model = 'text-ada-001',
    max_tokens = 100,
    top_p = 0.1
  },
  builder = function(input)
    return {
      prompt = input,
      stream = true
    }
  end
}

local function code_builder(input, context)
  local surrounding_lines_count = 30

  local text_before = util.string.join_lines(util.table.slice(context.before, -surrounding_lines_count))
  local text_after = util.string.join_lines(util.table.slice(context.after, 0, surrounding_lines_count))

  local instruction = 'Replace the token <@@> with valid code. Respond only with code, never respond with an explanation, never respond with a markdown code block containing the code. Generate only code that is meant to replace the token, do not regenerate code in the context.'

  local fewshot = {
    {
      role = 'user',
      content = 'The code:\n```\nfunction greet(name) { console.log("Hello " <@@>) }\n```\n\nExisting text at <@@>:\n```+ nme```\n'
    },
    {
      role = 'assistant',
      content = '+ name'
    }
  }

  local content = 'The code:\n```\n' .. text_before .. '<@@>' .. text_after .. '\n```\n'

  if #input > 0 then
    content = content ..  '\n\nExisting text at <@@>:\n```' .. input .. '```\n'
  end

  if #context.args > 0 then
    content = content .. context.args
  end

  local messages = {
    {
      role = 'user',
      content = content
    }
  }

  return {
    instruction = instruction,
    fewshot = fewshot,
    messages = messages,
  }
end

local function adapt_palm(standard_prompt)
  local function palm_message(msg)
    return {
      author = msg.role == 'user' and '0' or '1',
      content = msg.content
    }
  end

  local examples = {}

  local current_example = {}
  for _, example in ipairs(standard_prompt.fewshot) do
    if example.role == 'user' then
      current_example.input = palm_message(example)
    else
      current_example.output = palm_message(example)
    end

    if current_example.input and current_example.output then
      table.insert(examples, current_example)
      current_example = {}
    end
  end

  return {
    prompt = {
      context = standard_prompt.instruction,
      examples = examples,
      messages = vim.tbl_map(
        palm_message,
        standard_prompt.messages
      )
    }
  }
end

local function adapt_openai(standard_prompt)
  return {
    messages = util.table.flatten({
      {
        role = 'system',
        content = standard_prompt.instruction
      },
      standard_prompt.fewshot,
      standard_prompt.messages
    }),
  }
end

local function extract_schema_descripts(url, cb)
  -- TODO extract component references
  util.async(function(wait, resolve)
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

local function extract_markdown_code(text)
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

  local extracted = _extract_markdown_code(text)
  if extracted == '' then
    return text
  else
    return extracted
  end
end

--- Gets the relevant api route from an Open API schema url by asking gpt and parsing the result.
--- Callback resolves with:
--- {
---   schema: table,
---   relevant_route: table
--- }
local function gpt_ask_relevant_path(schema, task, callback)
  util.async(function(wait, resolve)
    local gpt_prompt =
      'This api is:\n' .. schema.description
      .. '\n\nThese are the routes:\n'
      .. vim.json.encode(schema.routes)
      .. '\n\nWhich one would be useful in this task:\n'
      .. task
      .. '\n\nRespond with a json object of the path and method. Respond only with valid json, do not include an explanation e.g.:\n'
      .. [[`{ "path": "/somepath", "method": "post" }`]]

    local gpt_consistent = vim.tbl_extend('force', gpt, {
      params = {
        temperature = 0.0,
        model = "gpt-3.5-turbo-0301"
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

return {
  gpt = gpt,
  localhost = vim.tbl_extend('force', gpt, {
    options = {
      url = 'http://127.0.0.1:8000/v1/'
    }
  }),
  ada = ada,
  kobold = {
    provider = kobold,
    builder = function(input)
      return {
        prompt = input,
        max_content_length = 2048,
        max_length = 200,
        top_p = 0.92
      }
    end
  },
  palm = {
    provider = palm,
    builder = function(input)
      return {
        prompt = {
          messages = {
            {
              content = input
            }
          }
        }
      }
    end
  },
  ['huggingface bigcode'] = {
    provider = huggingface,
    params = {
      model = 'bigcode/starcoder'
    },
    builder = function(input)
      return { inputs = input }
    end
  },
  ['huggingface bloom'] = {
    provider = huggingface,
    params = {
      model = 'bigscience/bloom'
    },
    builder = function(input)
      return { inputs = input }
    end
  },
  code = {
    provider = openai,
    mode = llm.mode.INSERT_OR_REPLACE,
    params = {
      temperature = 0.2,
      max_tokens = 1000,
      model = 'gpt-3.5-turbo-0301'
    },
    builder = function(input, context)
      return adapt_openai(code_builder(input, context))
    end,
    transform = extract_markdown_code
  },
  ['ask code'] = {
    provider = openai,
    mode = llm.mode.BUFFER,
    params = {
      temperature = 0.2,
      max_tokens = 1000,
      model = 'gpt-3.5-turbo-0301'
    },
    builder = function(input, context)
      local surrounding_lines_count = 10

      local text_before = util.string.join_lines(util.table.slice(context.before, -surrounding_lines_count))
      local text_after = util.string.join_lines(util.table.slice(context.after, 0, surrounding_lines_count))

      local messages = {
        {
          role = 'user',
          content = vim.inspect({
            text_after = text_after,
            text_before = text_before,
            text_selected = context.selection ~= nil and input or nil
          })
        }
      }

      if #context.args > 0 then
        table.insert(messages, {
          role = 'user',
          content = context.args
        })
      end

      return { messages = messages }
    end
  },
  ['palm code'] = {
    provider = palm,
    mode = llm.mode.INSERT_OR_REPLACE,
    builder = function(input, context)
      return adapt_palm(code_builder(input, context))
    end,
    transform = extract_markdown_code
  },
  instruct = {
    provider = openai,
    params = {
      temperature = 0.3,
      max_tokens = 1500
    },
    mode = llm.mode.REPLACE,
    builder = function(input)
      local messages = {
        {
          role = 'user',
          content = input
        }
      }

      return util.builder.user_prompt(function(user_input)
        if #user_input > 0 then
          table.insert(messages, {
            role = 'user',
            content = user_input
          })
        end

        return {
          messages = messages
        }
      end, input)
    end,
  },
  ask = {
    provider = openai,
    params = {
      temperature = 0.3,
      max_tokens = 1500
    },
    mode = llm.mode.BUFFER,
    builder = function(input, context)
      local details = context.segment.details()
      local row = details.row -1
      vim.api.nvim_buf_set_lines(details.bufnr, row, row, false, {''})

      local args_seg = segment.create_segment_at(row, 0, 'Question', details.bufnr)
      args_seg.add(context.args)

      return {
        messages = {
          {
            role = 'user',
            content = input
          },
          {
            role = 'user',
            content = context.args
          }
        }
      }
    end,
  },
  ['commit message'] = {
    provider = openai,
    mode = llm.mode.INSERT,
    builder = function()
      local git_diff = vim.fn.system {'git', 'diff', '--staged'}

      if not git_diff:match('^diff') then
        vim.notify(vim.fn.system('git status'), vim.log.levels.ERROR)
        return
      end

      return {
        messages = {
          {
            role = 'user',
            content = 'Write a terse commit message according to the Conventional Commits specification. Try to stay below 80 characters total. Staged git diff: ```\n' .. git_diff .. '\n```'
          }
        }
      }
    end,
  },
  ['commit review'] = {
    provider = openai,
    mode = llm.mode.BUFFER,
    builder = function()
      local git_diff = vim.fn.system {'git', 'diff', '--staged'}
      -- TODO extract relevant code from store

      return {
        messages = {
          {
            role = 'user',
            content = 'Review this code change: ```\n' .. git_diff .. '\n```'
          }
        }
      }
    end,
  },
  openapi = {
    -- Extract the relevant path from an OpenAPI spec and include in the gpt request.
    -- Expects schema url as a command arg.
    provider = openai,
    builder = function(input, context)
      if context.args == nil or #context.args == 0 then
        error('Provide the schema url as a command arg (:Llm openapi https://myurl.json)')
      end

      local schema_url = context.args

      return function(build)
        util.async(function(wait, resolve)
          local schema = wait(extract_schema_descripts(schema_url, resolve))
          util.show(schema.description, 'got openapi schema')

          local route = wait(gpt_ask_relevant_path(schema, input, resolve))
          util.show(route.relevant_route, 'api relevant route')

          return {
            messages = {
              {
                role = 'user',
                content =
                  "API schema url: " .. schema_url
                  .. "\n\nAPI description: " .. route.schema.description
                  .. "\n\nRelevant path:\n" .. vim.json.encode(route.relevant_route)
              },
              {
                role = 'user',
                content = input
              }
            }
          }
        end, build)
      end
    end
  }
}
