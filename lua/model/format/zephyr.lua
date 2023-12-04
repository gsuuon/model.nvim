local M = {}

---Format ChatContents to a string list so they can be individually tokenized.
---reference: https://huggingface.co/HuggingFaceH4/zephyr-7b-beta
---@param messages ChatMessage[]
---@param system string
---@return string[]
local function contents_to_strings(messages, system)
  local result = {
    '<|system|>\n' .. system
  }

  for _,msg in ipairs(messages) do
    table.insert(result, '\n<|' ..  msg.role .. '|>\n' .. msg.content)
  end

  table.insert(result, '\n<|assistant|>\n')

  return result
end

function M.content_to_prompt(messages, config)
  return table.concat(
    contents_to_strings(messages, config.system or 'You are a helpful assistant'),
    '</s>\n' -- llama.cpp seems to correctly stop generating if we just have </s> strings in prompt now
             -- may need a stop = {'</s>'} if not, or use the tokenizing runner
  )
end

return M
