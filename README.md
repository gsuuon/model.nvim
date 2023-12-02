# 🧠 llm.nvim

Use LLM's in Neovim. Build editor integrated prompts and customize your LLM workflow. This plugin comes with some starter prompts out of the box but it's designed for those who want to customize their prompts, experiment with multiple providers or use local LLM's. All prompts are in lua and can be instantly-reloaded.

https://user-images.githubusercontent.com/6422188/233238173-a3dcea16-9948-4e7c-a419-eeec04cb7e99.mp4

### Features

- 🎪 OpenAI GPT (and compatible API's), Google PaLM, Huggingface, LlamaCpp, Kobold
- 🛸 Add LLM capabilities from other Neovim plugins
- 🎨 Build your own editor integrated completions
- 🔎 Basic local (to your git repo) vector store
- 🌠 Streaming responses where available

### Contents
- [Setup](#-setup)
- [Usage](#-usage)
- [Config](#configuration)
- [Reference](#reference)
- [Examples](#examples)
- [Contributing](#contributing)

If you have any questions feel free to ask in [discussions](https://github.com/gsuuon/llm.nvim/discussions)!

---

## 🦾 Setup

### Requirements
- Nvim 0.8.0 or higher
- curl
- For the OpenAI provider (default), set the `OPENAI_API_KEY` environment variable to your [api key](https://platform.openai.com/account/api-keys)
- For the PaLM provider, set the `PALM_API_KEY` environment variable to your [api key](https://makersuite.google.com/app/apikey)

#### Optional
For local vector store:
- Python 3.10+
- `pip install numpy openai tiktoken`

### With [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
require('packer').startup(function(use)
  use 'gsuuon/llm.nvim'
end)
```
### With [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
require('lazy').setup({
  {
    'gsuuon/llm.nvim',
    cmd = { 'Llm', 'LlmChat' }
  }
})
```

## 💭 Usage

llm.nvim comes with some [starter prompts](./lua/llm/prompts/starters.lua) and makes it easy to build your own prompt library. For an example of a more complex agent-like multi-step prompt (e.g. curl, ask gpt for intermediate data, then include data in a final prompt) look at the `openapi` starter prompt.

It can also be used from another plugin to easily add LLM capabilities, for an example look at [note.nvim](https://github.com/gsuuon/note.nvim/blob/main/lua/note/llm/prompts.lua) which adds some [buffer-local](https://github.com/gsuuon/note.nvim/blob/main/ftplugin/note.lua) prompts to note files.

### Commands

- `:Llm [prompt-name]` — Start a completion of either the visual selection or the current buffer. Uses the default prompt if no prompt name is provided.

<details>
<summary>
Select response
</summary>

https://github.com/gsuuon/llm.nvim/assets/6422188/fd5aca13-979f-4bcf-8570-f935fdebbf03

</details>

- `:LlmSelect` — Select the response under the cursor.  

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
Check the module functions exposed in [store](./lua/llm/store/init.lua). This uses the OpenAI embeddings api to generate vectors and queries them by cosine similarity.

To add items call into the `llm.store` lua module functions, e.g.
  - `:lua require('llm.store').add_lua_functions()`
  - `:lua require('llm.store').add_files('.')`

Look at `store.add_lua_functions` for an example of how to use treesitter to parse files to nodes and add them to the local store.

To get query results call `store.prompt.query_store` with your input text, desired count and similarity cutoff threshold (0.75 seems to be decent). It returns a list of {id: string, content: string}:

```lua
builder = function(input, context)
  ---@type {id: string, content: string}[]
  local store_results = require('llm.store').prompt.query_store(input, 2, 0.75)

  -- add store_results to your messages
end
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
All setup options are optional. Add new prompts to `options.prompts.[name]` and chat prompts to `options.chats.[name]`.

```lua
---@class SetupOptions
---@field default_prompt? Prompt the default prompt (`:Llm` with no argument)
---@field prompts? table<string, Prompt> add prompts (`:Llm [name]`)
---@field chats? table<string, ChatPrompt> add chat prompts (`:LlmChat [name]`)
---@field hl_group? string set the default highlight group of in-progress responses
---@field join_undo? boolean join streaming response text as a single `u` undo. use if you intend to wait for responses to finish before editing other text, as edits during streaming will also be undone.

require('llm').setup({
  default_prompt = {},
  prompts = {...},
  chats = {...},
  hl_group = 'Comment',
  join_undo = false,
})
```

### Prompts

Prompts go in the `prompts` field of the setup table and are ran by the command `:Llm [prompt name]` which will tab complete the available prompts.

With lazy.nvim:
```lua
{
  'gsuuon/llm.nvim',
  config = function()
    require('llm').setup({
      prompts = {
        instruct = { ... },
        code = { ... },
        ask = { ... }
      }
    })
  end
}
```

A prompt entry defines how to handle a completion request - it takes in the editor input (either an entire file or a visual selection) and some context, and produces the api request data merging with any defaults. It also defines how to handle the API response - for example it can replace the selection (or file) with the response or insert it at the cursor positon.

Check out the [starter prompts](./lua/llm/prompts/starters.lua) to see how to create prompts. Type definitions are in [provider.lua](./lua/llm/provider.lua).


### Chat prompts
Chat prompts go in `setup({ prompts = {..}, chats = { [name] = { <chat prompt> }, .. } })` next to `prompts`.

Chat prompts have a different API than regular prompts. Use `:LlmChat my_chat` to create a new llmchat buffer with the `my_chat` chat prompt. You can save the buffer with `.llmchat` extension and continue the chat later with `:LlmChat` using the same settings (shown in the header). It's a normal buffer so you can edit messages or settings as needed. `llmchat` comes with some syntax highlighting to show the various parts - name of the chatprompt runner, options and params in the header, and a system message. The header and llm responses have fold levels set.

### Library autoload
You can use `require('util').module.autoload` instead of a naked `require` to always re-require a module on use. This makes the feedback loop for developing prompts faster:

```diff
require('llm').setup({
-  prompts = require('prompt_library')
+  prompts = require('llm.util').module.autoload('prompt_library')
})
```

I recommend setting this only during active prompt development, and switching to a normal `require` otherwise.

### Providers
#### OpenAI ChatGPT (default)
Set the environment variable `OPENAI_API_KEY` to your [api key](https://platform.openai.com/account/api-keys) before starting nvim. OpenAI prompts can take an additional option field with a table containing `{ url?, endpoint?, authorization?, curl_args? }` fields to talk to compatible API's. Check the `compat` starter prompt for an example.

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

#### Google PaLM
Set the `PALM_API_KEY` environment variable to your [api key](https://makersuite.google.com/app/apikey).

Check the palm prompt in [starter prompts](./lua/llm/prompts/starters.lua) for a reference. Palm provider defaults to the chat model (`chat-bison-001`). The builder's return params can include `model = 'text-bison-001'` to use the text model instead.

Params should be either a [generateMessage](https://developers.generativeai.google/api/rest/generativelanguage/models/generateMessage#request-body) body by default, or a [generateText](https://developers.generativeai.google/api/rest/generativelanguage/models/generateText#request-body) body if using `model = 'text-bison-001'`.

```lua
['palm text completion'] = {
  provider = palm,
  builder = function(input, context)
    return {
      model = 'text-bison-001',
      prompt = {
        text = input
      },
      temperature = 0.2
    }
  end
}
```

#### Huggingface API
Set the `HUGGINGFACE_API_KEY` environment variable to your [api key](https://huggingface.co/settings/tokens).

Set the model field on the params returned by the builder (or the static params in `prompt.params`). Set `params.stream = false` for models which don't support it (e.g. `gpt2`). Check [huggingface api docs](https://huggingface.co/docs/api-inference/detailed_parameters) for per-task request body types.

```lua
['huggingface bigcode'] = {
  provider = huggingface,
  params = {
    model = 'bigcode/starcoder'
  },
  builder = function(input)
    return { inputs = input }
  end
}
```

#### LlamaCpp

This provider uses the [llama.cpp server](https://github.com/ggerganov/llama.cpp/blob/master/examples/server/README.md).

You can start the server manually or have it autostart when you run a llamacpp prompt. To autostart the server call `require('llm.providers.llamacpp').setup({})` in your config function and set a `model` in the prompt options (see below). Leave `model` empty to not autostart. The server restarts if the prompt model or args change.

##### Setup
1. Build [llama.cpp](https://github.com/ggerganov/llama.cpp)
1. Download the model you want to use, e.g. [Zephyr 7b beta](https://huggingface.co/TheBloke/zephyr-7B-beta-GGUF/tree/main)
1. Setup the llamacpp provider if you plan to use autostart:
    ```lua
    config = function()
      require('llm').setup({ .. })

      require('llm.providers.llamacpp').setup({
        server = {
          binary = '~/path/to/server/binary',
          models = '~/path/to/models/directory'
        }
      })
    end
    ```
1. Use the llamacpp provider in a prompt:
    ```lua
    local llamacpp = require('llm.providers.llamacpp')

    require('llm').setup({
      prompts = {
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
                .. '</s>\n<|assistant|>',
              stops = { '</s>' }
            }
          end
        }
      }
    })
    ```

Llamacpp setup options:
 - `server?.binary: string` - path to the llamacpp server binary executable
 - `server?.models: string` - path to the parent directory of the models (joined with `prompt.model`)

Llamacpp prompt options:
 - `options.model?: string` - use with `require('llm.providers.llamacpp').setup()` to autostart the server with this model.
 - `options.args?: string[]` - additional arguments for the server.
 - `options.url?: string` - url of the server. Defaults to http://localhost:8080.


#### Codellama
This is a llama.cpp based provider specialized for codellama infill / Fill in the Middle. Only 7B and 13B models support FIM, and the base models (not Instruct) seem to work better. Start the llama.cpp server example with one of the two supported models before using this provider.

#### Kobold
For older models that don't work with llama.cpp, koboldcpp might still support them. Check their [repo](https://github.com/LostRuins/koboldcpp/) for setup info.

#### Adding your own
Providers implement a simple interface so it's easy to add your own. Just set your provider as the `provider` field in a prompt. Your provider needs to kick off the request and call the handlers as data streams in, finishes, or errors. Check [the hf provider](./lua/llm/providers/huggingface.lua) for a simpler example supporting server-sent events streaming. If you don't need streaming, just make a request and call `handler.on_finish` with the result.

```lua
---@class Provider
---@field request_completion fun(handler: StreamHandlers, params?: table, options?: table): function Request a completion stream from provider, returning a cancel callback

---@class StreamHandlers
---@field on_partial (fun(partial_text: string): nil) Partial response of just the diff
---@field on_finish (fun(complete_text: string, finish_reason: string): nil) Complete response with finish reason
---@field on_error (fun(data: any, label?: string): nil) Error data and optional label
```

Basic provider example:
```lua
{
  prompts = {
    test = {
      provider = {
        request_completion = function(handlers, params, options)
          vim.notify(vim.inspect({params=params, options=options}))
          handlers.on_partial('a response')
          handlers.on_finish()
        end
      },
      builder = function(input, context)
        return {
          input = input,
          context = context
        }
      end
    }
  }
}
```

--- 

## Reference
**SetupOptions**

Setup `require('llm').setup(SetupOptions)`
- `default_prompt?: string` - The default prompt to use with `:Llm`. Default is the openai starter.
- `prompts?: {string: Prompt}` - A table of custom prompts to use with `:Llm [name]`. Keys are the names of the prompts. Default are the starters.
- `chats?: {string: ChatPrompt}` - A table of chat prompts to use with `:LlmChat [name]`. Keys are the names of the chats.
- `hl_group?: string` - The default highlight group for in-progress responses. Default is `'Comment'`.
- `join_undo?: boolean` - Whether to join streaming response text as a single undo command. When true, unrelated edits during streaming will also be undone. Default is `true`.

**Prompt**

Setup `require('llm').setup({prompts = { [name] = Prompt, .. }})`  
Run `:Llm [prompt name]`
- `provider: Provider` - The API provider for this prompt, responsible for requesting and returning completion suggestions.
- `builder: ParamsBuilder` - Converts input (either the visual selection or entire buffer text) and context to request parameters. Returns either a table of params or a function that takes a callback with the params.
- `transform?: fun(string): string` - Optional function that transforms completed response text after on_finish, e.g. to extract code.
- `mode?: SegmentMode | StreamHandlers` - Response handling mode. Defaults to 'append'. Can be one of 'append', 'replace', 'buffer', 'insert', or 'insert_or_replace'.
- `hl_group?: string` - Highlight group of active response.
- `params?: table` - Static request parameters for this prompt.
- `options?: table` - Optional options for the provider.

**Provider**
- `request_completion: fun(handler: StreamHandlers, params?: table, options?: table): function` - Requests a completion stream from the provider and returns a cancel callback. Feeds completion parts back to the prompt runner using handler methods and calls on_finish after completion is done.
- `default_prompt? : Prompt` - Default prompt for this provider (optional).
- `adapt?: fun(prompt: StandardPrompt): table` - Adapts a standard prompt to params for this provider (optional).

**ParamsBuilder** (function)
- `fun(input: string, context: Context): table | fun(resolve: fun(params: table))` - Converts input and context to request data. Returns either a table of params or a function that takes a callback with the params.

**SegmentMode** (enum)

Exported as 
```lua
local llm = require('llm')
llm.mode.--
```
- `APPEND = 'append'` - Append to the end of input.
- `REPLACE = 'replace'` - Replace input.
- `BUFFER = 'buffer'` - Create a new buffer and insert.
- `INSERT = 'insert'` - Insert at the cursor position.
- `INSERT_OR_REPLACE = 'insert_or_replace'` - Insert at the cursor position if no selection, or replace the selection.

**StreamHandlers**
- `on_partial: fun(partial_text: string): nil` - Called by the provider to pass partial incremental text completions during a completion request.
- `on_finish: fun(complete_text?: string, finish_reason?: string): nil` - Called by the provider when the completion is done. Takes an optional argument for the completed text (`complete_text`) and an optional argument for the finish reason (`finish_reason`).
- `on_error: fun(data: any, label?: string): nil` - Called by the provider to pass error data and an optional label during a completion request.

**ChatPrompt**

Setup `require('llm').setup({chats = { [name] = ChatPrompt, .. }})`  
Run `:LlmChat [chat prompt name]`
- `provider: APIProvider` - The API provider for this chat prompt. This field contains the specific implementation of the chat feature being used.
- `create: fun(input: string, context: Context): string | ChatContents` - Converts input and context into the first message text or ChatContents, which are written into the new chat buffer.
- `run: fun(messages: ChatMessage[], config: ChatConfig): table | fun(resolve: fun(params: table): nil )` - Converts chat messages and configuration into completion request parameters. This function returns a table containing the required parameters for generating completions, or it can return a function that takes a callback to resolve the parameters.
- `system?: string` - Optional system instruction used to provide specific instructions for the API provider.
- `params?: table` - Static request parameters that are provided to the API provider during completion generation.
- `options?: table` - Provider options, which can be customized by the user to modify the chat prompt behavior.

**ChatMessage**
- `role: 'user' | 'assistant'` - Indicates whether this message was generated by the user or the assistant.
- `content: string` - The actual content of the message.

**ChatConfig**
- `system?: string` - Optional system instruction used to provide context or specific instructions for the API provider.
- `params?: table` - Static request parameters that are provided to the API provider during completion generation.
- `options?: table` - Provider options, which can be customized by the user to modify the chat prompt behavior.

**ChatContents**
- `config: ChatConfig` - Configuration for this chat buffer, used by `chatprompt.run`. This includes information such as the system instruction, static request parameters, and provider options.
- `messages: ChatMessage[]` - Messages in the chat buffer.

## Examples

### Prompts

```lua
require('llm').setup({
  prompts = {
    ['prompt name'] = ...
  }
})
```

<details>
<summary>Ask for additional user instruction</summary>

https://github.com/gsuuon/llm.nvim/assets/6422188/0e4b2b68-5873-42af-905c-3bd5a0bdfe46

```lua
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
  }
```

</details>

<details>
<summary>Create a commit message based on `git diff --staged`</summary>

https://user-images.githubusercontent.com/6422188/233807212-d1830514-fe3b-4d38-877e-f3ecbdb222aa.mp4

```lua
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
local segment = require('llm.util.segment')

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
local segment = require('llm.util.segment')

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

## Contributing
New starter prompts, providers and bug fixes are welcome! If you've figured out some useful prompts and want to share, check out the [discussions](https://github.com/gsuuon/llm.nvim/discussions/24).

### Roadmap
I'm hoping to eventually add the following features - I'd appreciate help with any of these.

#### Local retrieval augmented generation
The basics are here - a simple json vectorstore based on the git repo, querying, cosine similarity comparison. It just needs a couple more features to improve the DX of using from prompts.

#### Enhanced context
Make treesitter and LSP info available in prompt context.

#### Chat mode
A split buffer for chat usage. I still just use web UI's for chat, but having RAG enhanced chats would be nice.
