---@class StandardMessage
---@field role 'assistant' | 'user'

---@class StandardPrompt
---@field instruction? string
---@field fewshot? StandardMessage[]
---@field messages StandardMessage[]

local util = require('llm.util')

local M = {}

function M.limit_before_after(context, line_count)
  return {
    before = util.string.join_lines(util.table.slice(context.before, -line_count)),
    after = util.string.join_lines(util.table.slice(context.after, 0, line_count))
  }
end

return M
