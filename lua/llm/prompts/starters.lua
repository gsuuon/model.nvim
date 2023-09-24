local llm = require('llm')

local segment = require('llm.segment')

local util = require('llm.util')
local async = require('llm.util.async')

local prompts = require('llm.prompts')
local extract = require('llm.prompts.extract')
local consult = require('llm.prompts.consult')

local openai = require('llm.providers.openai')
local palm = require('llm.providers.palm')
local huggingface = require('llm.providers.huggingface')
local kobold = require('llm.providers.kobold')
local llamacpp = require('llm.providers.llamacpp')

local function standard_code(input, context)
  local surrounding_text = prompts.limit_before_after(context, 30)

  local instruction = 'Start generating the code which should replace the special token <@@> in the following code, keeping sure to have consistent whitespace.'

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

  local content = 'The code:\n```\n' .. surrounding_text.before .. '<@@>' .. surrounding_text.after .. '\n```\n'

  if context.selection then -- we only use input if we have a visual selection
    content = content ..  '\n\nExisting text at <@@>:\n```' .. input .. '```\n'
  end

  if #context.args > 0 then
    content = content .. '\nInstruction: ' .. context.args
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

return {
  gpt = openai.default_prompt,
  palm = palm.default_prompt,
  hf = huggingface.default_prompt,
  compat = vim.tbl_extend('force', openai.default_prompt, {
    options = {
      url = 'http://127.0.0.1:8000/v1/'
    }
  }),
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
  llamacpp = {
    provider = llamacpp,
    params = {
      model = 'models/llama-2-13b-chat.ggmlv3.q4_K_M.bin',
      ['n-gpu-layers'] = 32,
      threads = 6,
      ['repeat-penalty'] = 1.2,
      temp = 0.2,
      ['ctx-size'] = 4096,
      ['n-predict'] = -1
    },
    builder = function(input)
      return {
        prompt = llamacpp.llama_2_format({
          messages = {
            input
          }
        })
      }
    end,
    options = {
      path = os.getenv('LLAMACPP_DIR'),
      main_dir = os.getenv('LLAMACPP_MAIN_DIR')
    }
  },
  ['hf starcoder'] = {
    provider = huggingface,
    options = {
      model = 'bigcode/starcoder'
    },
    builder = function(input)
      return { inputs = input }
    end
  },
  code = {
    provider = openai,
    mode = llm.mode.INSERT_OR_REPLACE,
    params = {
      temperature = 0.1,
      max_tokens = 500,
      model = 'gpt-3.5-turbo-0613'
    },
    builder = function(input, context)
      return openai.adapt(standard_code(input, context))
    end,
    transform = extract.markdown_code
  },
  ['code palm'] = {
    provider = palm,
    mode = llm.mode.INSERT_OR_REPLACE,
    builder = function(input, context)
      return palm.adapt(standard_code(input, context))
    end,
    transform = extract.markdown_code
  },
  ['code gpt4'] = {
    provider = openai,
    mode = llm.mode.INSERT_OR_REPLACE,
    params = {
      temperature = 0.2,
      max_tokens = 1000,
      model = 'gpt-4'
    },
    builder = function(input, context)
      return openai.adapt(standard_code(input, context))
    end,
    transform = extract.markdown_code
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
  ['ask code'] = {
    provider = openai,
    mode = llm.mode.BUFFER,
    params = {
      temperature = 0.2,
      max_tokens = 1000,
      model = 'gpt-3.5-turbo-0301'
    },
    builder = function(input, context)
      local surrounding_text = prompts.limit_before_after(context, 30)

      local messages = {
        {
          role = 'user',
          content = vim.inspect({
            text_after = surrounding_text.after,
            text_before = surrounding_text.before,
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
  ['ask commit review'] = {
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

      return function(build)
        vim.ui.input(
          {
          prompt = 'Additional instruction for prompt: '
        }, function(user_input)
          if user_input == nil then return end

          if #user_input > 0 then
            table.insert(messages, {
              role = 'user',
              content = user_input
            })
          end

          build({
            messages = messages
          })
        end)
      end
    end,
  },
  commit = {
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
        async(function(wait, resolve)
          local schema = wait(extract.schema_descripts(schema_url, resolve))
          util.show(schema.description, 'got openapi schema')

          local route = wait(consult.gpt_relevant_openapi_schema_path(schema, input, resolve))
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
