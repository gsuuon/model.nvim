# 🧠 llm.nvim

Talk to Large Language Model AI in Neovim.

https://user-images.githubusercontent.com/6422188/233238173-a3dcea16-9948-4e7c-a419-eeec04cb7e99.mp4


- 🪁 __Streaming responses__  
- 📑 __Build a prompt library__  
- 🌞 __Super easy__  

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

- `:Llm [prompt-name]` — Start a completion of either the visual selection or the current buffer. If you've added alternative [prompts](#prompts) to the config, you can give a prompt name as an argument. Streaming text is added on the next line in visual line-wise mode, or from the end of the selection in char-wise visual mode.

- `:LlmMulti` — Start multiple prompt completions at the same time with the same input. Must specify prompt names. Escape spaces in names e.g. `to\ spanish`, or use tab completion. Always completes on next line and always `mode = 'append'`.

- `:LlmCancel` — Cancel the active response under the cursor.

- `:LlmShow` — Flash the response under the cursor.

- `:LlmDelete` — Delete the response under the cursor. If `prompt.mode == 'replace'` then replace with the original text.

## Providers
### OpenAI ChatGPT (default)
Set the environment variable `OPENAI_API_KEY` to your [api key](https://platform.openai.com/account/api-keys) before starting nvim.

#### Configuration
Add default request parameters for [/chat/completions](https://platform.openai.com/docs/api-reference/chat/create) with `initialize()`:
```
require('llm.providers.openai').initialize({
  max_tokens = 120,
  temperature = 0.7,
  model = 'gpt-3.5-turbo-0301'
})
```

## 🧵Configuration
### Prompts
A prompt entry requires the builder and provider fields. The field is a function that converts the input selection into data for the body of a request. You can optionally change the highlighting group of an active response, and if the response should replace or append to the selection (defaults to append)

#### `@class Prompt`
```lua
---@field provider Provider The API provider for this prompt
---@field builder PromptBuilder Converts input and context to request data
---@field hl_group? string Highlight group of active response
---@field mode? SegmentMode | StreamHandlers Response handling mode ("replace" | "append" | StreamHandlers). Defaults to "append".
```

#### `@class StreamHandlers`
```lua
---@field on_partial (fun(partial_text: string): nil) Partial response of just the diff
---@field on_finish (fun(complete_text: string, finish_reason: string): nil) Complete response with finish reason
---@field on_error (fun(data: any, label?: string): nil) Error data and optional label
```

#### `require('llm').setup()`
- `default_prompt: Prompt` — modify the default prompt  

- `prompts: table<string, Prompt>` — add prompt alternatives  
  Alternatives can be used by calling `:Llm` with their name, e.g. `:Llm advice` (fuzzy command completion)

#### Example

<details>
<summary>prompt that replaces text with Spanish</summary>

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
<summary>prompt that notifies each stream part and the complete response</summary>

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


### Appearance
- `hl_group: string`  
  — Set the default highlight group of in-progress responses

### Autoload
The `util` module has a helpful function to make developing prompts easier - `M.module.autoload`. Use this instead of `require` on a module that exports your prompt library to always use what's currently on disk.

--- 

### Example configuration
You can move prompts into their own file and use `util.module.autoload` to quickly iterate on prompt development.

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

#### `prompt_library.lua`
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
