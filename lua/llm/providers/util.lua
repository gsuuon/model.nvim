local util = require('llm.util')

local M = {}

function M.iter_sse_items(raw_data, fn)
  local items = util.string.split_pattern(raw_data, 'data:')
  -- FIXME it seems like sometimes we don't get the two newlines?

  for _, item in ipairs(items) do
    if #item > 0 then
      fn(item)
    end
  end
end

-- local text = [[data: {"a": true}
-- data: {"b": true}

-- data: {"c": true}
-- ]]

-- M.iter_sse_items(text, function(x)
--   local x = util.json.decode(x)
--   show({
--     item = x
--   }, 'item')
-- end)

return M
