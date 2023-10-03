local llm = require('llm')
local openai = require('llm.providers.openai')

local extract = require('llm.prompts.extract')

local function standard_code(input, context)

local prompts = require('llm.prompts')
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
  commit = {
    provider = openai,
    mode = llm.mode.INSERT_OR_REPLACE,
    builder = function(input, context)
      local git_diff = vim.fn.system({'git', 'diff', '--staged'})

      if git_diff == nil or not git_diff:match('^diff') then
        vim.notify(vim.fn.system('git status') or 'git command failed', vim.log.levels.ERROR)
        return
      end

      local content_instruction = 'Write a very short, terse commit message according to the Conventional Commits specification.'
      local content_diff = '\n```diff\n' .. git_diff .. '\n```'
      local content_hint = ''

      if context.selection then
        content_hint = '\nStart the commit message with `' .. input .. '`'
      end

      return tap({
        messages = {
          {
            role = 'user',
            content = content_instruction .. content_diff .. content_hint
          }
        }
      })
    end,
  }
}
