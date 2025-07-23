---@class StandardMessage
---@field role 'assistant' | 'user'

---@class StandardPrompt
---@field instruction? string
---@field fewshot? StandardMessage[]
---@field messages StandardMessage[]

local util = require('model.util')
local model_ctx = require('model.util.qflist')

---@param selection? Span
local function get_diagnostics(selection)
  local diagnostic_text = ''
  do
    local diagnostics
    do
      if selection == nil then
        diagnostics = vim.diagnostic.get(0)
      else
        local start_zero_idx = selection.start.row
        local stop_zero_idx = selection.stop.row

        diagnostics = vim.tbl_filter(function(d)
          local lnum = d.lnum
          return lnum >= start_zero_idx and lnum <= stop_zero_idx
        end, vim.diagnostic.get(0))
      end
    end

    if #diagnostics > 0 then
      local lines = { '\nDiagnostics:\n```' }

      for _, d in ipairs(diagnostics) do
        local severity = vim.diagnostic.severity[d.severity]
        table.insert(
          lines,
          string.format('[%s] L%d: %s', severity, d.lnum + 1, d.message)
        )
      end

      table.insert(lines, '```')
      diagnostic_text = table.concat(lines, '\n')
    end
  end

  return diagnostic_text
end

local M = {}

---@param context Context
---@param line_count number
---@return { before: string, after: string }
function M.limit_before_after(context, line_count)
  return {
    before = table.concat(util.table.slice(context.before, -line_count), '\n'),
    after = table.concat(util.table.slice(context.after, 0, line_count), '\n'),
  }
end

function M.context_with_quickfix_and_surroundings(input, context)
  return ([[
%s
The user is editing file `%s`

Before user cursor:
````
%s
````
%s
After user cursor:
````
%s
````
%s
Response format:
Write code that goes between the "Before user cursor" and "After user cursor" sections.
%s
]]):format(
    model_ctx.get_text(),
    context.filename,
    context.before,
    context.selection == nil
        and "There is no user selected text, respond only with text meant to go between the 'Before user cursor' and 'After user cursor' sections."
      or ([[
User selection:
````
%s
````
                ]]):format(input),
    context.after,
    get_diagnostics(context.selection),
    context.args == '' and '' or ('User instruction:\n' .. context.args)
  )
end

---@class ChatPromptPartial ChatPrompt with all fields optional
---@field provider? Provider The API provider for this prompt
---@field create? fun(input: string, context: Context): string | ChatContents Converts input and context to the first message text or ChatContents
---@field run? fun(messages: ChatMessage[], config: ChatConfig): table | fun(resolve: fun(params: table): nil ) ) Converts chat messages and config into completion request params
---@field runOptions? fun(): table Builds additional options to merge into chat prompt options. E.g. for auth tokens that shouldn't be written to the chat config header.
---@field system? string System instruction
---@field params? table Static request parameters
---@field options? table Provider options
---@field completion? ChatCompletionOptions

---@param source_prompt ChatPrompt
---@param partial_prompt ChatPromptPartial
function M.merge(source_prompt, partial_prompt)
  return util.merge(source_prompt, partial_prompt)
end

return M
