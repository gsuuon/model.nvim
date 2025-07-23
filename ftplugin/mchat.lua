if not vim.b.did_mchat_plugin then
  vim.api.nvim_create_user_command('MchatRun', function()
    local chat = require('model.core.chat')
    local model = require('model')

    chat.run_chat(model.opts)
  end, {
    desc = 'MchatRun',
    force = true,
  })

  vim.api.nvim_create_user_command('MToolPresentAgain', function(cmd)
    local model = require('model')
    local tools = require('model.util.tools')

    tools.run_presentation(model.opts.tools, cmd.fargs)
  end, {
    desc = 'Re-run the presentation effects of a tool call',
    force = true,
    nargs = '*',
    complete = function(arglead)
      local model = require('model')
      local tools = require('model.util.tools')

      local presentable = tools.get_presentable_tool_calls(model.opts.tools)

      if #arglead == 0 then
        return presentable
      end

      return vim.fn.matchfuzzy(presentable, arglead)
    end,
  })

  vim.keymap.set(
    'n',
    '<CR>',
    '<cmd>MchatRun<CR>',
    { buffer = true, silent = true }
  )

  vim.keymap.set('n', 'G', function()
    require('model').want_auto_scroll(vim.fn.bufnr(), true)

    vim.api.nvim_feedkeys('G', 'n', false)
  end, {
    buffer = true,
  })

  vim.keymap.set('n', 'k', function()
    require('model').want_auto_scroll(vim.fn.bufnr(), false)

    vim.api.nvim_feedkeys('k', 'n', false)
  end, {
    buffer = true,
  })

  vim.keymap.set('n', 'gg', function()
    require('model').want_auto_scroll(vim.fn.bufnr(), false)

    vim.api.nvim_feedkeys('gg', 'n', false)
  end, {
    buffer = true,
  })

  vim.api.nvim_create_user_command('MToolAutoAcceptByName', function(cmd)
    local model = require('model')
    local tools = require('model.util.tools')

    if #cmd.fargs == 0 then
      model.tool_auto_accept(vim.fn.bufnr(), nil)
    else
      model.tool_auto_accept(vim.fn.bufnr(), tools.accept_by_name(cmd.fargs))
    end
  end, {
    desc = 'Set auto accepting tools by tool name',
    force = true,
    nargs = '*',
    complete = function(arglead)
      local model = require('model')

      local tools = vim.tbl_keys(model.opts.tools)

      if #arglead == 0 then
        return tools
      end

      return vim.fn.matchfuzzy(tools, arglead)
    end,
  })

  vim.b.did_mchat_plugin = true
end
