-- providers
local openai = require('model.providers.openai')
local palm = require('model.providers.palm')
local huggingface = require('model.providers.huggingface')
local kobold = require('model.providers.kobold')
local llamacpp = require('model.providers.llamacpp')
local codellama = require('model.providers.codellama')
local together = require('model.providers.together')

-- prompt helpers
local chat = require('model.core.chat')
local extract = require('model.prompts.extract')
local consult = require('model.prompts.consult')
local llama2 = require('model.format.llama2')

-- utils
local util = require('model.util')
local async = require('model.util.async')
local prompts = require('model.util.prompts')
local mode = require('model').mode

local function standard_code(input, context)
  local surrounding_text = prompts.limit_before_after(context, 30)

  local instruction = 'You are an expert programmer. You are given a snippet of code which includes the symbol <@@>. Complete the correct code that should replace the <@@> symbol given the content. Only respond with the code that should replace the symbole <@@>. If you include any other code, the program will fail to compile and the user will be very sad.'

  local fewshot = {
    {
      role = 'user',
      content = 'The code:\n```\nfunction greet(name) { console.log("Hello " <@@>) }\n```\n\nExisting text at <@@>: `+ nme`'
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

---@type table<string, Prompt>
local starters = {
  gpt = openai.default_prompt,
  chat = {
    provider = openai,
    params = {
      model = 'gpt-3.5-turbo-0613'
    },
    transform = function(response)
      return '\n======\n' .. response .. '\n======\n\n'
    end,
    builder = function(input)
      if vim.o.ft ~= 'mchat' then
        error('Not in mchat buffer')
      end

      return chat.parse(input)
    end
  },
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
    builder = function(input, context)
      return {
        prompt = llama2.user_prompt({user = context.args or '', message = input})
      }
    end
  },
  zephyr = {
    provider = llamacpp,
    options = {
      model = 'zephyr-7b-beta.Q5_K_M.gguf',
      args = {
        '-c', 8192,
        '-ngl', 35
      }
    },
    builder = function(input, context)
      return {
        prompt =
          '<|system|>'
          .. (context.args or 'You are a helpful assistant')
          .. '\n</s>\n<|user|>\n'
          .. input
          .. '</s>\n<|assistant|>'
      }
    end
  },
  codellama = codellama.default_prompt,
  ['together/stripedhyena'] = {
    provider = together,
    params = {
      model = 'togethercomputer/StripedHyena-Nous-7B',
      max_tokens = 512
    },
    builder = function(input)
      return {
        prompt = '### Instruction:\n' .. input .. '\n\n### Response:\n',
        stop = '</s>'
      }
    end
  },
  ['together/phind-codellama34b_v2'] = {
    provider = together,
    params = {
      model = 'Phind/Phind-CodeLlama-34B-v2',
      max_tokens = 512
    },
    builder = function(input)
      return {
        prompt = '### System Prompt\nYou are an intellegient programming assistant\n\n### User Message\n' .. input  ..'\n\n### Assistant\n'
      }
    end
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
    mode = mode.INSERT_OR_REPLACE,
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
    mode = mode.INSERT_OR_REPLACE,
    builder = function(input, context)
      return palm.adapt(standard_code(input, context))
    end,
    transform = extract.markdown_code
  },
  ['code gpt4'] = {
    provider = openai,
    mode = mode.INSERT_OR_REPLACE,
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
  ['ask code'] = {
    provider = openai,
    mode = mode.BUFFER,
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
    mode = mode.BUFFER,
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
    mode = mode.REPLACE,
    builder = function(input)
      local messages = {
        {
          role = 'user',
          content = input
        }
      }

      return function(build)
        vim.ui.input(
          { prompt = 'Additional instruction for prompt: ' },
          function(user_input)
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
    mode = mode.INSERT,
    builder = function()
      local git_diff = vim.fn.system {'git', 'diff', '--staged'}

      if git_diff:match('^diff') then
        return {
          messages = {
            {
              role = 'user',
              content = 'Write a terse commit message according to the Conventional Commits specification. Try to stay below 80 characters total. Staged git diff: ```\n' .. git_diff .. '\n```'
            }
          }
        }
      end

      vim.notify(vim.fn.system('git status'), vim.log.levels.ERROR)
    end,
  },
  openapi = {
    -- Extract the relevant path from an OpenAPI spec and include in the gpt request.
    -- Expects schema url as a command arg.
    provider = openai,
    mode = mode.BUFFER,
    builder = function(input, context)
      if context.args == nil or #context.args == 0 then
        error('Provide the schema url as a command arg (:M openapi https://myurl.json)')
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

return starters
