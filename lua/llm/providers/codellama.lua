local llm = require('llm')
local prompts = require('llm.prompts')
local curl = require('llm.curl')
local util = require('llm.util')
local async = require('llm.util.async')
local provider_util = require('llm.providers.util')

--- This is a llamacpp based provider that only supports infill with codellama 7b and 13b, which require special token handling.
--- Note that the base models seem to perform better than Instruct models. I'm also not sure how to actually add instructions to a FIM prompt.
local M = {}


--- Special tokens taken from https://huggingface.co/mlc-ai/mlc-chat-CodeLlama-13b-hf-q4f16_1/raw/main/tokenizer.json
--- and https://github.com/facebookresearch/codellama/blob/cb51c14ec761370ba2e2bc351374a79265d0465e/llama/tokenizer.py#L28
local PRE = 32007
local MID = 32009
local SUF = 32008
local BOS = 1
local EOS = 2

---@param handlers StreamHandlers
---@param params { context: { before: string, after: string } }  -- before and after context along with generation options: https://github.com/ggerganov/llama.cpp/tree/master/examples/server#api-endpoints
---@param options { url?: string } Url to running llamacpp server root (defaults to http://localhost:8080/)
function M.request_completion(handlers, params, options)
  local cancel = nil

  local options_ = vim.tbl_extend('force', {
    url = 'http://localhost:8080/'
  }, options or {})

  local function request_tokens(text, on_complete)
    curl.request(
      {
        url = options_.url .. 'tokenize',
        body = {
          content = text
        }
      }, function(response)
        local data = util.json.decode(response)
        if data == nil then
          handlers.on_error('Failed to decode tokenizer response: ' .. response)
          error('Failed to decode tokenizer response: ' .. response)
          -- TODO probably want to add async error handling
        end

        on_complete(data.tokens)
      end,
      handlers.on_error
    )
  end

  async(
    function(wait, resolve)
      -- These rely on the fact that BOS is not added in tokenizer
      -- https://github.com/ggerganov/llama.cpp/blob/c091cdfb24621710c617ea85c92fcd347d0bf340/examples/server/README.md?plain=1#L165
      local pre_tokens = wait(request_tokens(params.context.before, resolve))
      local suf_tokens = wait(request_tokens(params.context.after, resolve))

      return {
        pre = pre_tokens,
        suf = suf_tokens
      }
    end,
    function(tokens)
      local prompt_tokens = vim.tbl_flatten({
        -- Reference: https://github.com/facebookresearch/codellama/blob/cb51c14ec761370ba2e2bc351374a79265d0465e/llama/generation.py#L404
        -- PSM format
        BOS,
        PRE,
        tokens.pre,
        SUF,
        tokens.suf,
        -- there might be additional magic here I'm not handling
        -- https://github.com/facebookresearch/codellama/blob/cb51c14ec761370ba2e2bc351374a79265d0465e/llama/generation.py#L407
        MID
      })

      local completion = ''

      cancel = curl.stream(
        {
          url = options_.url .. 'completion',
          body = vim.tbl_extend(
            'force',
            {
              stream = true,
              prompt = prompt_tokens
            },
            util.table.without(params, 'context')
          )
        },
        provider_util.iter_sse_data(function(data)
          local item = util.json.decode(data)

          if item == nil then
            handlers.on_error('Failed to decode: ' .. data)
          elseif item.stop then
            local strip_eot = completion:gsub(' <EOT>$', '') -- We can probably drop this eventually when llama.cpp adds the codellama special tokens (32010+)
            handlers.on_finish(strip_eot)
          else
            completion = completion .. item.content
            handlers.on_partial(item.content)
          end
          end),
        util.eshow
      )
    end
  )

  return function() cancel() end
end

M.default_prompt = {
  provider = M,
  mode = llm.mode.INSERT, -- weird things happen if we have a visual selection
  params = {
    temperature = 0.1,    -- Seems to rarely decode EOT if temp is high
    top_p = 0.9,
    n_predict = 256,      -- Server seems to be ignoring this?
    repeat_penalty = 1.2  -- infill really struggles with overgenerating
  },
  builder = function(_, context)
    -- we ignore input since this is just for FIM
    -- TODO figure out how to add instructions to FIM in Instruct models
    return {
      context = prompts.limit_before_after(context, 30)
    }
  end
}

return M
