# 🧠 llm.nvim

Talk to Large Language Model AI in Neovim.

https://user-images.githubusercontent.com/6422188/233238173-a3dcea16-9948-4e7c-a419-eeec04cb7e99.mp4


- 📑 __Build a prompt library__  
- 🐘 __Local vectorstore (wip)__
- 🪁 __Stream responses__  
- 🌞 __Super easy__  


Check out the [examples](#examples)


---

## 🦾 Setup

- Requires Nvim 0.8.0 or higher

### With [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use { 
  'gsuuon/llm.nvim',
  config = function()
    require('llm').setup()
  end
}
```
### With [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
require('lazy').setup({
  { 'gsuuon/llm.nvim', config = true }
})
```

## 💭 Usage

- `:Llm [prompt-name]` — Start a completion of either the visual selection or the current buffer. If you've added alternative [prompts](#prompts) to the config, you can give a prompt name as an argument.

<details>
<summary>
Delete response
</summary>

https://user-images.githubusercontent.com/6422188/233774216-4e100122-3a93-4dfb-a7c7-df50f1221bdd.mp4

</details>

- `:LlmDelete` — Delete the response under the cursor. If `prompt.mode == 'replace'` then replace with the original text.

<details>
<summary>
🚧 WIP - Local vector store 
</summary>

### Requirements
  - Python 3.10+
  - `pip install numpy openai tiktoken`

### Usage
Check the module functions exposed in [store](./lua/llm/store/init.lua).

To add items call into the `llm.store` lua module functions, e.g.
  - `:lua require('llm.store').add_lua_functions()`
  - `:lua require('llm.store').add_files('.')`

Check `store.add_lua_functions` for an example of how to use treesitter to parse files to nodes.

To use store query results in a prompt:
```lua
local store = require('llm.store')

return {
  ...
  builder = function(input, context)
    ---@type {id: string, content: string}[]
    local store_results = store.prompt.query_store(input, 2, 0.75)

    -- do things with store_results
  end
}
```

</details>

- `:LlmStore [command]`
  - `:LlmStore init` — initialize a store.json file at the closest git root directory
  - `:LlmStore query <query text>` — query a store.json

<details>
<summary>
Multiple simultaneous prompts
</summary>

https://user-images.githubusercontent.com/6422188/233773433-d3b38147-540c-44ba-96ac-af2af8640e7c.mp4

</details>

- `:LlmMulti` — Start multiple prompt completions at the same time with the same input. Must specify prompt names. Escape spaces in names e.g. `to\ spanish`, or use tab completion. Always completes on next line and always `mode = 'append'`.

<details>
<summary>
Cancel a long-running prompt
</summary>

https://user-images.githubusercontent.com/6422188/233773436-3e9d2a15-bc87-47c2-bc5b-d62d62480297.mp4

</details>

- `:LlmCancel` — Cancel the active response under the cursor.

<details>
<summary>
Show response
</summary>

https://user-images.githubusercontent.com/6422188/233773449-3b85355b-bad1-4e40-a699-6a8f5cf4bcd5.mp4

</details>

- `:LlmShow` — Flash the response under the cursor if there is one.


## 🧵Configuration

```lua
require('llm').setup({
  default_prompt? = .. , -- Prompt — modify the default prompt (`:Llm` with no argument)
  prompts? = {}, -- table<string, Prompt>` — add prompt alternatives
  hl_group? = '' -- string — Set the default highlight group of in-progress responses
})
```

### Prompts

Prompts go in the `prompts` field of the setup table and can be used via `:Llm [prompt name]`.

A prompt entry defines how to handle a completion request - it takes in the editor input (either an entire file or a visual selection) and some context, and produces the api request data merging with any defaults. It also defines how to handle the API response - for example it can replace the selection (or file) with the response or insert it at the cursor positon.

Check the [examples](#examples) section to see how to define prompts. The type definitions are in [provider.lua](./lua/llm/provider.lua)

### Library autoload
You can use `require('util').module.autoload` instead of a naked `require` to always re-require a module on use. This makes the feedback loop for developing prompts faster:

```diff
require('llm').setup({
-  prompts = require('prompt_library')
+  prompts = require('llm.util').module.autoload('prompt_library')
})
```

### Providers
#### OpenAI ChatGPT (default)
Set the environment variable `OPENAI_API_KEY` to your [api key](https://platform.openai.com/account/api-keys) before starting nvim.

<details>
<summary>
Configuration
</summary>

Add default request parameters for [/chat/completions](https://platform.openai.com/docs/api-reference/chat/create) with `initialize()`:

```
require('llm.providers.openai').initialize({
  max_tokens = 120,
  temperature = 0.7,
  model = 'gpt-3.5-turbo-0301'
})
```

</details>

--- 

## Examples

### Prompts

These examples go in the prompts field. Prompt names can have spaces.

```lua
require('llm').setup({
  prompts = {
    ['prompt name'] = ...
  }
})
```

<details>
<summary>Get additional user instruction</summary>

https://github.com/gsuuon/llm.nvim/assets/6422188/0e4b2b68-5873-42af-905c-3bd5a0bdfe46

```lua
local util = require('llm.util')
local segment = require('llm.segment')

...
  ['with instruction'] = {
    provider = openai,
    builder = function(input)
      return util.builder.user_prompt(function(user_input)
        return {
          messages = {
            {
              role = 'user',
              content = input
            },
            {
              role = 'user',
              content = user_input
            }
          }
        }
      end, input)
    end,
    mode = segment.mode.REPLACE
  }
```

</details>

<details>
<summary>Create a commit message based on `git diff --staged`</summary>

https://user-images.githubusercontent.com/6422188/233807212-d1830514-fe3b-4d38-877e-f3ecbdb222aa.mp4

```lua
  commit = {
    provider = openai,
    builder = function()
      return {
        messages = {
          {
            role = 'system',
            content = 'Write a commit message according to the Conventional Commits specification for the following git diff. Keep it as short as necessary. If only markdown files are changed, use `docs: `'
          },
          {
            role = 'user',
            content = vim.fn.system {'git', 'diff', '--staged'}
          }
        }
      }
    end
  }
```

</details>

<details>
<summary>Modify input to append messages</summary>

https://user-images.githubusercontent.com/6422188/233748890-5dac719a-eb9a-4f76-ab9d-8eba3694a350.mp4


#### `lua/prompt_library.lua`
```lua
--- Looks for `<llm:` at the end and splits into before and after
--- returns all text if no directive
local function match_llm_directive(text)
  local before, _, after = text:match("(.-)(<llm:)%s?(.*)$")
  if not before and not after then
    before, after = text, ""
  elseif not before then
    before = ""
  elseif not after then
    after = ""
  end
  return before, after
end

local instruct_code = 'You are a highly competent programmer. Include only valid code in your response.'

return {
  ['to code'] = {
    provider = openai,
    builder = function(input)
      local text, directive = match_llm_directive(input)

      local msgs ={
        {
          role = 'system',
          content = instruct_code,
        },
        {
          role = 'user',
          content = text,
        }
      }

      if directive then
        table.insert(msgs, { role = 'user', content = directive })
      end

      return {
        messages = msgs
      }
    end,
    mode = segment.mode.REPLACE
  },
  code = {
    provider = openai,
    builder = function(input)
      return {
        messages = {
          {
            role = 'system',
            content = instruct_code,
          },
          {
            role = 'user',
            content = input,
          }
        }
      }
    end,
  },
}
```

</details>


<details>
<summary>Replace text with Spanish</summary>

```lua
local openai = require('llm.providers.openai')
local segment = require('llm.segment')

require('llm').setup({
  prompts = {
    ['to spanish'] =
      {
        provider = openai,
        hl_group = 'SpecialComment',
        builder = function(input)
          return {
            messages = {
              {
                role = 'system',
                content = 'Translate to Spanish',
              },
              {
                role = 'user',
                content = input,
              }
            }
          }
        end,
        mode = segment.mode.REPLACE
      }
  }
})
```

</details>

<details>
<summary>Notifies each stream part and the complete response</summary>

```lua
local openai = require('llm.providers.openai')

require('llm').setup({
  prompts = {
    ['show parts'] = {
      provider = openai,
      builder = openai.default_builder,
      mode = {
        on_finish = function (final)
          vim.notify('final: ' .. final)
        end,
        on_partial = function (partial)
          vim.notify(partial)
        end,
        on_error = function (msg)
          vim.notify('error: ' .. msg)
        end
      }
    },
  }
})
```

</details>



### Configuration
You can move prompts into their own file and use `util.module.autoload` to quickly iterate on prompt development.

<details>
<summary>Setup</summary>

#### `config = function()`

```lua
local openai = require('llm.providers.openai')

-- configure default model params here for the provider
openai.initialize({
  model = 'gpt-3.5-turbo-0301',
  max_tokens = 400,
  temperature = 0.2,
})

local util = require('llm.util')

require('llm').setup({
  hl_group = 'Substitute',
  prompts = util.module.autoload('prompt_library'),
  default_prompt = {
    provider = openai,
    builder = function(input)
      return {
        temperature = 0.3,
        max_tokens = 120,
        messages = {
          {
            role = 'system',
            content = 'You are helpful assistant.',
          },
          {
            role = 'user',
            content = input,
          }
        }
      }
    end
  }
})
```
</details>


<details>
<summary>Prompt library</summary>

#### `lua/prompt_library.lua`

```lua
local openai = require('llm.providers.openai')
local segment = require('llm.segment')

return {
  code = {
    provider = openai,
    builder = function(input)
      return {
        messages = {
          {
            role = 'system',
            content = 'You are a 10x super elite programmer. Continue only with code. Do not write tests, examples, or output of code unless explicitly asked for.',
          },
          {
            role = 'user',
            content = input,
          }
        }
      }
    end,
  },
  ['to spanish'] = {
    provider = openai,
    hl_group = 'SpecialComment',
    builder = function(input)
      return {
        messages = {
          {
            role = 'system',
            content = 'Translate to Spanish',
          },
          {
            role = 'user',
            content = input,
          }
        }
      }
    end,
    mode = segment.mode.REPLACE
  },
  ['to javascript'] = {
    provider = openai,
    builder = function(input, ctx)
      return {
        messages = {
          {
            role = 'system',
            content = 'Convert the code to javascript'
          },
          {
            role = 'user',
            content = input
          }
        }
      }
    end,
  },
  ['to rap'] = {
    provider = openai,
    hl_group = 'Title',
    builder = function(input)
      return {
        messages = {
          {
            role = 'system',
            content = "Explain the code in 90's era rap lyrics"
          },
          {
            role = 'user',
            content = input
          }
        }
      }
    end,
  }
}
```

</details>

