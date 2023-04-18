# 🧠 llm.nvim

Talk to Large Language Model AI in Neovim.

![demo](https://user-images.githubusercontent.com/6422188/232323471-2fe0bb1f-54a3-4508-b6fb-b9c6d091dde8.gif)

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

`:Llm` - complete either the visual selection or the current buffer. Completion is added on the next line in visual line-wise mode, or from the end of the selection in char-wise visual mode.

### Providers
#### OpenAI ChatGPT (default)
Set the environment variable `OPENAI_API_KEY` to your [api key](https://platform.openai.com/account/api-keys) before starting nvim.


## 🧵Configuration

### Prompt builders
`@alias prompt_builder fun(input: string, context: table): table`

Prompt builders are specific to a provider. They take the input (selected text or entire file), some context (filename) and produce a request body that gets merged into the default body.

- `providers.<provider name>.prompts.1`  
  — modify the default prompt  

- `providers.<provider name>.prompts.<alternative name>`  
  — add prompt alternatives  
  Alternatives can be used with `:Llm` by providing their name, e.g. `:Llm advice`


### Appearance
- `responding_hl_group = <hl_group>`  
  — Set highlight group of in-progress responses
  

```lua
use {
  'gsuuon/llm.nvim',
  config = function()
    require('llm').setup({
      responding_hl_group = 'Substitute',
      providers = {
        openai = {
          prompts = {
            function(input, _ctx)
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
            advice = function(input)
              return {
                messages = {
                  {
                    role = 'system',
                    content = 'You are a wise advisor, ',
                  },
                  {
                    role = 'user',
                    content = input,
                  }
                }
              }
            end
          }
        }
      }
    })
  end
}
```
