# llm.nvim

Use LLM's in Neovim buffers. Currently works with OpenAI's ChatGPT API - just set `OPENAI_API_KEY` in environment before starting nvim.

![demo](https://user-images.githubusercontent.com/6422188/232323471-2fe0bb1f-54a3-4508-b6fb-b9c6d091dde8.gif)

## setup

With Packer
```lua
use({
  "~/code/gsuuon/llm.nvim",
  config = function()
    require("llm").setup()

    -- or, to customize the prompt
    require("llm").setup({
      responding_hl_group = "Substitute",
      providers = {
        openai = {
          prompt_builder = function(input, _ctx)
            return {
              messages = {
                {
                  role = "system",
                  content = "You are a 10x super elite programmer. Continue only with code. Do not write tests, examples, or output of code unless explicitly asked for.",
                },
                {
                  role = "user",
                  content = input,
                }
              }
            }
          end
        }
      }
    })
  end
})
```

## usage

`:Llm` - complete a visual selection or the current buffer. Completion continues on the next line in visual line-wise mode, otherwise from the end of the selection in char-wise visual mode.
