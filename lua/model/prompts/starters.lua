-- providers
local openai = require('model.providers.openai')
local palm = require('model.providers.palm')
local huggingface = require('model.providers.huggingface')
local llamacpp = require('model.providers.llamacpp')
local together = require('model.providers.together')
local ollama = require('model.providers.ollama')

-- prompt helpers
local extract = require('model.prompts.extract')
local consult = require('model.prompts.consult')

-- utils
local util = require('model.util')
local async = require('model.util.async')
local prompts = require('model.util.prompts')
local mode = require('model').mode

local function code_replace_fewshot(input, context)
  local surrounding_text = prompts.limit_before_after(context, 30)

  local content = 'The code:\n```\n'
    .. surrounding_text.before
    .. '<@@>'
    .. surrounding_text.after
    .. '\n```\n'

  if context.selection then -- we only use input if we have a visual selection
    content = content .. '\n\nExisting text at <@@>:\n```' .. input .. '```\n'
  end

  if #context.args > 0 then
    content = content .. '\nInstruction: ' .. context.args
  end

  local messages = {
    {
      role = 'user',
      content = content,
    },
  }

  return {
    instruction = 'You are an expert programmer. You are given a snippet of code which includes the symbol <@@>. Complete the correct code that should replace the <@@> symbol given the content. Only respond with the code that should replace the symbol <@@>. If you include any other code, the program will fail to compile and the user will be very sad.',
    fewshot = {
      {
        role = 'user',
        content = 'The code:\n```\nfunction greet(name) { console.log("Hello " <@@>) }\n```\n\nExisting text at <@@>: `+ nme`',
      },
      {
        role = 'assistant',
        content = '+ name',
      },
    },
    messages = messages,
  }
end

---@type table<string, Prompt>
local starters = {
  gpt = openai.default_prompt,
  palm = palm.default_prompt,
  hf = huggingface.default_prompt,
  ['llamacpp:zephyr'] = {
    provider = llamacpp,
    options = {
      model = 'zephyr-7b-beta.Q5_K_M.gguf',
      args = {
        '-c',
        8192,
        '-ngl',
        35,
      },
    },
    builder = function(input, context)
      return {
        prompt = '<|system|>'
          .. (context.args or 'You are a helpful assistant')
          .. '\n</s>\n<|user|>\n'
          .. input
          .. '</s>\n<|assistant|>',
      }
    end,
  },
  ['together:stripedhyena'] = {
    provider = together,
    params = {
      model = 'togethercomputer/StripedHyena-Nous-7B', -- 32k model
      max_tokens = 1024,
    },
    builder = function(input)
      return {
        prompt = '### Instruction:\n' .. input .. '\n\n### Response:\n',
        stop = '</s>',
      }
    end,
  },
  ['together:phind/codellama34b_v2'] = {
    provider = together,
    params = {
      model = 'Phind/Phind-CodeLlama-34B-v2', -- 16k model
      max_tokens = 1024,
    },
    builder = function(input)
      return {
        prompt = '### System Prompt\nYou are an intelligent programming assistant\n\n### User Message\n'
          .. input
          .. '\n\n### Assistant\n',
      }
    end,
  },
  ['ollama:starling'] = {
    provider = ollama,
    params = {
      model = 'starling-lm',
    },
    builder = function(input)
      return {
        prompt = 'GPT4 Correct User: '
          .. input
          .. '<|end_of_turn|>GPT4 Correct Assistant: ',
      }
    end,
  },
  ['hf:starcoder'] = {
    provider = huggingface,
    options = {
      model = 'bigcode/starcoder',
    },
    builder = function(input)
      return { inputs = input }
    end,
  },
  ['openai:gpt4-code'] = {
    provider = openai,
    mode = mode.INSERT_OR_REPLACE,
    params = {
      temperature = 0.2,
      max_tokens = 1000,
      model = 'gpt-4',
    },
    builder = function(input, context)
      return openai.adapt(code_replace_fewshot(input, context))
    end,
    transform = extract.markdown_code,
  },
  commit = {
    provider = openai,
    mode = mode.INSERT,
    builder = function()
      local git_diff = vim.fn.system({ 'git', 'diff', '--staged' })

      if not git_diff:match('^diff') then
        error('Git error:\n' .. git_diff)
      end

      return {
        messages = {
          {
            role = 'user',
            content = 'Write a terse commit message according to the Conventional Commits specification. Try to stay below 80 characters total. Staged git diff: ```\n'
              .. git_diff
              .. '\n```',
          },
        },
      }
    end,
  },
  openapi = {
    -- Extract the relevant path from an OpenAPI spec and include in the gpt request.
    -- Expects schema url as a command arg.
    provider = openai,
    mode = mode.BUFFER,
    builder = function(input, context)
      if context.args == nil or #context.args == 0 then
        error(
          'Provide the schema url as a command arg (:M openapi https://myurl.json)'
        )
      end

      local schema_url = context.args

      return function(build)
        async(function(wait, resolve)
          local schema = wait(extract.schema_descripts(schema_url, resolve))
          util.show(schema.description, 'got openapi schema')

          local route = wait(
            consult.gpt_relevant_openapi_schema_path(schema, input, resolve)
          )
          util.show(route.relevant_route, 'api relevant route')

          return {
            messages = {
              {
                role = 'user',
                content = 'API schema url: '
                  .. schema_url
                  .. '\n\nAPI description: '
                  .. route.schema.description
                  .. '\n\nRelevant path:\n'
                  .. vim.json.encode(route.relevant_route),
              },
              {
                role = 'user',
                content = input,
              },
            },
          }
        end, build)
      end
    end,
  },
}

return starters
