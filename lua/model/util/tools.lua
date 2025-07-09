local util = require('model.util')
local chat = require('model.core.chat')

---@class ToolCall
---@field id string id of call
---@field name string name of tool
---@field arguments string JSON encoded arguments

local function process_partial_tool_call(handle_fields)
  local args = ''

  local completed_fields = {}
  local current_field = ''

  local function partial_field(text)
    handle_fields[current_field].part(text)
  end

  local function complete_field()
    handle_fields[current_field].complete()
    completed_fields[current_field] = true
    current_field = ''
  end

  ---@param arg_partial string
  return function(arg_partial)
    if args == '' then
      -- check if we got the entire arguments object in one go
      -- e.g. when re-running presentation
      local all_args = util.json.decode(arg_partial)
      if all_args then
        for field, handle in pairs(handle_fields) do
          handle.part(all_args[field])
          handle.complete()
        end
      end
    end

    -- TODO if we get an arg_partial which adds more than 1 field, this breaks
    local next_args = args .. arg_partial

    if current_field == '' then
      local arg_attempt = util.json.decode(next_args .. '"}')
      if arg_attempt ~= nil then
        for field in pairs(handle_fields) do
          if arg_attempt[field] ~= nil and completed_fields[field] == nil then
            current_field = field

            partial_field(arg_attempt[field])
          end
        end
      end
    else
      -- this won't match if " is the first char, since we test for \
      local ending = arg_partial:match('^(.*[^\\])"')
      -- if our preceding args didn't end with an escape char and our new partial starts with a quote
      -- we're immediately closing the string
      local immediate_close = args:match('[^\\]$') and arg_partial:match('^"')

      if immediate_close then
        complete_field()
      elseif ending then
        partial_field(ending)
        complete_field()
      else
        partial_field(arg_partial)
      end
    end

    args = next_args
  end
end

---@param available_tools table<string, Tool>
---@param allowed_tools boolean | string[] true for all, nil or false for none, list of strings to filter
local function equip_tools(available_tools, allowed_tools)
  ---@type table<string, Tool>
  local equipped_tools = {}

  if allowed_tools == nil or type(allowed_tools) == 'boolean' then
    if allowed_tools == true then
      for tool_name in util.module.autopairs(available_tools) do
        equipped_tools[tool_name] = available_tools[tool_name]
      end
    end
  else
    if vim.islist(allowed_tools) then
      for _, tool_name in pairs(allowed_tools) do
        if available_tools[tool_name] then
          equipped_tools[tool_name] = available_tools[tool_name]
        else
          util.eshow('Missing tool: ' .. tool_name)
        end
      end
    end
  end

  return equipped_tools
end

---@param message ChatMessage
local function get_all_tool_calls(message)
  ---@type ToolCall[]
  local tool_calls = {}

  for _, section in ipairs(message.data_sections or {}) do
    if section.label == 'tool_calls' then
      local section_tool_calls = util.json.decode(section.content)

      for _, tool_call in ipairs(section_tool_calls or {}) do
        table.insert(tool_calls, tool_call)
      end
    end
  end

  return tool_calls
end

---Gets the tool calls for tools which the tool is enabled and it has a presentation
local function get_can_present_tool_calls(equipped_tools, bufnr_or_lines)
  local lines
  do
    if type(bufnr_or_lines) == 'number' then
      lines = vim.api.nvim_buf_get_lines(bufnr_or_lines or 0, 0, -1, false)
    elseif type(bufnr_or_lines) == 'table' then
      lines = bufnr_or_lines
    else
      lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    end
  end

  local parsed = chat.parse(lines)
  local messages = parsed.contents.messages

  if #messages == 0 then
    error('No messages')
  end

  local last_message = messages[#messages]

  local tool_calls = get_all_tool_calls(last_message)

  ---@type ToolCall[]
  local tool_calls_can_present = vim.tbl_filter(function(tool_call)
    local tool = equipped_tools[tool_call.name]
    return tool and tool.presentation ~= nil
  end, tool_calls)

  return tool_calls_can_present
end

---@return string[] tool_call_ids
local function get_presentable_tool_calls(equipped_tools)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local presentable = get_can_present_tool_calls(equipped_tools, lines)

  return vim.tbl_map(function(tool_call)
    return tool_call.id
  end, presentable)
end

--- @param bufnr_or_lines? integer | string[] buffer number or lines, nil for current buffer
--- @param target_tool_call_id? string id of tool call, or nil for all
local function run_presentation(
  equipped_tools,
  bufnr_or_lines,
  target_tool_call_id
)
  local tool_calls_with_presentation =
    get_can_present_tool_calls(equipped_tools, bufnr_or_lines)

  local tool_calls_to_present = target_tool_call_id
      and (vim.tbl_filter(function(tool_call)
        return tool_call.id == target_tool_call_id
      end, tool_calls_with_presentation))
    or tool_calls_with_presentation

  for _, call in ipairs(tool_calls_to_present) do
    local tool = equipped_tools[call.name]
    local consume_partials = tool.presentation()
    consume_partials(call.arguments)
  end
end

---@param bufnr integer
---@param equipped_tools table<string, Tool>
---@param message ChatMessage
---@param acceptor fun(call: ToolCall): boolean
local function autoaccept(bufnr, equipped_tools, message, acceptor)
  local tool_calls = get_all_tool_calls(message)
  local accept_status = {}

  local function continue_completion()
    if
      #vim.tbl_filter(function(x)
        return x
      end, accept_status) == #accept_status
    then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd('MchatRun')
      end)
    else
      util.show('Review tool calls then continue')
    end
  end

  local function maybe_done()
    -- check if all tool_calls have been run or accept_status
    if #accept_status == #tool_calls then
      continue_completion()
    end
  end

  for _, call in ipairs(tool_calls) do
    if acceptor(call) then
      local tool = equipped_tools[call.name]

      if tool then
        table.insert(accept_status, true)

        if tool.presentation_autoaccept then
          tool.presentation_autoaccept(call.arguments, function()
            maybe_done()
          end)
        else
          maybe_done()
        end
      else
        util.eshow('Missing tool: ' .. call.name)
        table.insert(accept_status, false)
        maybe_done()
      end
    else
      table.insert(accept_status, false)
      maybe_done()
    end
  end
end

local function accept_by_name(tool_names)
  return function(call)
    if vim.tbl_contains(tool_names, call.name) then
      return true
    end
    return false
  end
end

local function accept_by_arguments(acceptors)
  ---@param call ToolCall
  return function(call)
    local tool_acceptor = acceptors[call.name]
    if not tool_acceptor then
      return false
    end

    if tool_acceptor == true then
      return true
    end

    local args = util.json.decode(call.arguments)
    if not args then
      return false
    end

    for field, validator in pairs(tool_acceptor) do
      local arg_value = args[field]

      if type(validator) == 'function' then
        if not validator(arg_value) then
          return false
        end
      else
        if arg_value ~= validator then
          return false
        end
      end
    end

    return true
  end
end

return {
  process_partial_tool_call = process_partial_tool_call,
  get_all_tool_calls = get_all_tool_calls,
  run_presentation = run_presentation,
  equip_tools = equip_tools,
  get_presentable_tool_calls = get_presentable_tool_calls,
  autoaccept = autoaccept,
  accept_by_name = accept_by_name,
  accept_by_arguments = accept_by_arguments,
}
