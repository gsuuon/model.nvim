# 🧠 llm.nvim

Talk to Large Language Model AI in Neovim.

![demo](https://user-images.githubusercontent.com/6422188/232323471-2fe0bb1f-54a3-4508-b6fb-b9c6d091dde8.gif)

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

- `:Llm` — Start a completion of either the visual selection or the current buffer  
  Streaming text is added on the next line in visual line-wise mode, or from the end of the selection in char-wise visual mode.

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
Options for `require('llm').setup()`

### Prompts
A prompt entry requires the builder and provider fields. The builder field of a prompt is a function that converts the input selection into data for the body of a request. You can optionally change the highlighting group of an active response

```lua
---@class Prompt
---@field provider Provider The API provider for this prompt
---@field builder fun(input: string, context: table): table
--- Takes selected text and converts to data that's merged with the provider's default request body
---@field hl_group? string Highlight group of active response
```

- `default_prompt: Prompt` — modify the default prompt  

- `prompts: table<string, Prompt>` — add prompt alternatives  
  Alternatives can be used by calling `:Llm` with their name, e.g. `:Llm advice` (fuzzy command completion)

#### Example
```lua
local openai = require('llm.providers.openai')

{
  provider = openai,
  hl_group = 'SpecialComment',
  builder = function(input)
    return {
      messages = {
        {
          role = 'user',
          content = input,
        }
      }
    }
  end
}
```

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
  max_tokens = 4096,
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
        model = 'gpt-3.5-turbo-0301',
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
  comment = {
    provider = openai,
    builder = function(input, ctx)
      return {
        messages = {
          {
            role = 'system',
            content = 'Rewrite the code and add inline comments explaining the code.'
          },
          {
            role = 'user',
            content = input
          }
        }
      }
    end,
  },
  explain = {
    provider = openai,
    builder = function(input, ctx)
      return {
        messages = {
          {
            role = 'system',
            content = 'Explain the code.'
          },
          {
            role = 'user',
            content = input
          }
        }
      }
    end,
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

