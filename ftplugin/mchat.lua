if not vim.b.did_mchat_plugin then
  vim.api.nvim_create_user_command('MchatRun', function()
    local chat = require('model.core.chat')
    local model = require('model')

    chat.run_chat(model.opts)
  end, {
    desc = 'MchatRun',
    force = true,
  })

  vim.api.nvim_create_user_command('MchatToolPresentation', function(cmd)
    local tools = require('model.util.tools')
    tools.run_presentation(cmd.fargs[1])
  end, {
    desc = 'Re-run the presentation of a tool call',
    force = true,
    nargs = '?',
    complete = function(arglead)
      local tools = require('model.util.tools')
      local presentable = tools.get_presentable_tool_calls()

      if #arglead == 0 then
        return presentable
      end

      return vim.fn.matchfuzzy(presentable, arglead)
    end,
  })

  vim.b.did_mchat_plugin = true
end
