--- tool that allows one ai role to hand over to another ai role
--- do it by parsing the current mchat filetype buffer (error if it's not one)
--- then rewriting the same but changing the handler part to the one in the function arguments
--- the function may also pass a system instruction which can be set
--- the rest of the messages are written out the same as the original
--- modify the current buffer in place
return {
  description = 'Hand over chat to another AI role',
  parameters = {
    type = 'object',
    properties = {
      to = {
        type = 'string',
        description = 'Name of AI role to hand over to',
      },
      system = {
        type = 'string',
        description = 'Optional new system instruction (overrides target chat system)',
      },
    },
    required = { 'to' },
  },
  invoke = function(args)
    local ft = vim.bo.filetype

    if ft ~= 'mchat' then
      error('Current buffer is not an mchat file')
    end

    -- Get target chat prompt
    local chat_prompt = require('model').opts.chats[args.to]
    if not chat_prompt then
      error('Chat prompt "' .. args.to .. '" not found')
    end

    -- Schedule buffer replacement after current operation completes
    vim.defer_fn(function()
      local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      -- Parse the current chat buffer
      local parsed = require('model.core.chat').parse(buf_lines)

      -- Update config with target chat's properties
      parsed.contents.config = {
        system = args.system or chat_prompt.system,
        params = chat_prompt.params,
        options = chat_prompt.options,
      }

      -- Convert back to string with new handler name
      local new_content =
        require('model.core.chat').to_string(parsed.contents, args.to)

      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(new_content, '\n'))
    end, 200) -- give time to allow other schedule wrapped functions to complete. async tool calls in the same turn will break this

    return 'Handing over chat to ' .. args.to
  end,
}
