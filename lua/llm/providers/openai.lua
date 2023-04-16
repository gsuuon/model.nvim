local curl = require("plenary.curl")
local util = require("llm.util")

local M = {}

function M.authenticate()
  M.api_key = util.env("OPENAI_API_KEY")
end

function M.request(endpoint, body, opts)
  local defaults = {
    headers = {
      Authorization = "Bearer " .. M.api_key,
      ["Content-Type"] = "application/json"
    },
    compressed = false,
    body = vim.json.encode(body),
    raw = "-N"
  }

  local options = vim.tbl_deep_extend("force", defaults, opts)

  return curl.post(endpoint, options)
end

function M.extract_data(event_string)
  local success, data = pcall(util.json.decode, event_string:gsub('data: ', ''))

  if success then
    return {
      content = data.choices[1].delta.content,
      finish_reason = data.choices[1].finish_reason
    }
  end
end

function M.request_completion_stream(prompt, on_partial, on_finish, params)
  local params = params or {}

  local _content = ""

  return M.request( "https://api.openai.com/v1/chat/completions",
    vim.tbl_deep_extend("force", {
      model = "gpt-3.5-turbo",
      messages = {
        {
          role = "user",
          content = prompt
        }
      },
      stream = true,
    }, params), {
      stream = function(_, raw_data)
        if raw_data ~= "" then
          local data = M.extract_data(raw_data)
          if data ~= nil then
            if data.content ~= nil then
              _content = _content .. data.content
              on_partial(data.content)
            end

            if data.finish_reason ~= nil then
              on_finish(_content, data.finish_reason)
            end
          end
        end
      end
    }
  )
end

return M
