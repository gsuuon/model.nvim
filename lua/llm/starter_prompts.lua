local llm = require('llm')
local util = require('llm.util')
local openai = require('llm.providers.openai')

return {
  code = {
    provider = openai,
    mode = llm.mode.INSERT_OR_REPLACE,
    params = {
      temperature = 0.2,
      max_tokens = 1000
    },
    builder = function(input, context)
      local surrounding_lines_count = 20

      local text_before = util.string.join_lines(util.table.slice(context.before, -surrounding_lines_count))
      local text_after = util.string.join_lines(util.table.slice(context.after, 0, surrounding_lines_count))

      local content = 'The text: ```' .. text_before .. '<@@>' .. text_after .. '```'

      if #input > 0 then
        content = content .. '\n\nExisting text at <@@>: ```' .. input .. '```'
      end

      return {
        messages = {
          {
            role = 'user',
            content = content .. '\n\nRespond with raw text to replace the token <@@> in the text. Do not include explanations. Do not include surrounding markers in the response.'
          }
        }
      }
    end
  },
  ask = {
    provider = openai,
    params = {
      temperature = 0.3,
      max_tokens = 1500
    },
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
  ['commit message'] = {
    provider = openai,
    mode = llm.mode.INSERT,
    builder = function()
      local git_diff = vim.fn.system {'git', 'diff', '--staged'}
      return {
        messages = {
          {
            role = 'system',
            content = 'Write a short commit message according to the Conventional Commits specification for the following git diff: ```\n' .. git_diff .. '\n```'
          }
        }
      }
    end,
  }
}
