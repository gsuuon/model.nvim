---@class StandardMessage
---@field role 'assistant' | 'user'

---@class StandardPrompt
---@field instruction? string
---@field fewshot? StandardMessage[]
---@field messages StandardMessage[]

local util = require('model.util')

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

return M
