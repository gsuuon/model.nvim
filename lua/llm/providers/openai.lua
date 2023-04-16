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
    body = vim.json.encode(body)
  }

  local options = vim.tbl_deep_extend("force", defaults, opts)

  return curl.post(endpoint, options)
end

function M.request_completion_stream(prompt, on_partial, on_finish, params)
  local params = params or {}

  local function extract_data(event_string)
    return util.json.decode(event_string:gsub('data: ', ''))
  end

  local function get_content(data)
    return data.choices[1].delta.content
  end

  local function get_finish_reason(data)
    return data.choices[1].finish_reason
  end

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
      stream = true
    }, params), {
      stream = function(_, raw_data)
        if raw_data ~= "" then
          local success, data = pcall(extract_data, raw_data)
          if success then
            local content = get_content(data)

            if content ~= nil then
              _content = _content .. content
              on_partial(content)
            end

            local finish_reason = get_finish_reason(data)

            if finish_reason ~= nil then
              on_finish(_content, finish_reason)
            end
          end
        end
      end
    }
  )
end

return M
