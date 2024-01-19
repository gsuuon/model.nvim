local openai = require('model.providers.openai')
local palm = require('model.providers.palm')
local llamacpp = require('model.providers.llamacpp')
local ollama = require('model.providers.ollama')
local together = require('model.providers.together')

local zephyr_fmt = require('model.format.zephyr')
local starling_fmt = require('model.format.starling')

local function input_if_selection(input, context)
  return context.selection and input or ''
end

local openai_chat = {
  provider = openai,
  system = 'You are a helpful assistant',
  params = {
    model = 'gpt-3.5-turbo-1106',
  },
  create = input_if_selection,
  run = function(messages, config)
    if config.system then
      table.insert(messages, 1, {
        role = 'system',
        content = config.system,
      })
    end

    return { messages = messages }
  end,
}

---@type table<string, ChatPrompt>
local chats = {
  openai = openai_chat,
  gpt4 = vim.tbl_deep_extend('force', openai_chat, {
    params = {
      model = 'gpt-4-1106-preview',
    },
  }),
  palm = {
    provider = palm,
    system = 'You are a helpful assistant',
    create = input_if_selection,
    options = {
      method = 'generateMessage',
      model = 'chat-bison-001',
    },
    run = function(messages, config)
      return {
        prompt = {
          context = config.system,
          messages = vim.tbl_map(function(msg)
            return {
              content = msg.content,
              author = msg.role,
            }
          end, messages),
        },
      }
    end,
  },
  ['llamacpp:zephyr'] = {
    provider = llamacpp,
    options = {
      model = 'zephyr-7b-beta.Q5_K_M.gguf',
      args = {
        '-c',
        8192,
        '-ngl',
        30,
      },
    },
    system = 'You are a helpful assistant',
    create = input_if_selection,
    run = zephyr_fmt.chat,
  },
  ['ollama:starling'] = {
    provider = ollama,
    params = {
      model = 'starling-lm',
    },
    create = input_if_selection,
    run = starling_fmt.chat,
  },
  ['together:codellama'] = {
    provider = together,
    params = {
      model = 'Phind/Phind-CodeLlama-34B-v2',
      max_tokens = 1000,
      stop = '</s>',
    },
    system = 'You are an intelligent programming assistant',
    create = function(input, ctx)
      return ctx.selection and input or ''
    end,
    run = function(messages, config)
      local prompt = '### System Prompt\n' .. config.system

      for _, msg in ipairs(messages) do
        prompt = prompt
          .. '\n\n### '
          .. (msg.role == 'user' and 'User Message' or 'Assistant')
          .. '\n'
          .. msg.content
      end

      prompt = prompt .. '### Assistant\n'

      return {
        prompt = prompt,
      }
    end,
  },
  ['together:mixtral'] = {
    provider = together,
    params = {
      model = 'DiscoResearch/DiscoLM-mixtral-8x7b-v2',
      temperature = 0.7,
      top_p = 0.7,
      top_k = 50,
      repetition_penalty = 1,
      stop = {
        '<|im_end|>',
        '<|im_start|>',
      },
    },
    create = input_if_selection,
    run = function(messages, config)
      local first = messages[1]

      if config.system then
        first.content = config.system .. '\n' .. first.content
      end

      return {
        prompt = table.concat(vim.tbl_map(function(msg)
          return '<|im_start|>'
            .. msg.role
            .. '\n'
            .. msg.content
            .. '<|im_end|>\n'
        end, messages)) .. '<|im_start|>assistant',
      }
    end,
  },
  ['gpt4:commit review'] = {
    provider = openai,
    system = "You are an expert programmer that gives constructive feedback. Review the changes in the user's git diff.",
    params = {
      model = 'gpt-4-1106-preview',
    },
    create = function()
      local git_diff = vim.fn.system({ 'git', 'diff', '--staged' })
      ---@cast git_diff string

      if not git_diff:match('^diff') then
        error('Git error:\n' .. git_diff)
      end

      return git_diff
    end,
    run = openai_chat.run,
  },
}

return chats
