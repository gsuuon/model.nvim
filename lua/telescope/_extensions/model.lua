local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local utils = require('telescope.utils')

local chat = require('model.core.chat')

local Previewer = require('telescope.previewers.previewer')

local function get_mchat_buffers()
  return vim.tbl_filter(function(bufnr)
    return vim.api.nvim_get_option_value('filetype', { buf = bufnr }) == 'mchat'
  end, vim.api.nvim_list_bufs())
end

local function entry_maker(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local display = lines[1]

  local chat_buf = chat.parse(lines)
  if chat_buf.contents.config.system then
    display = display .. ' > ' .. chat_buf.contents.config.system
  end

  display = display .. ' [' .. tostring(#chat_buf.contents.messages) .. ']'

  return {
    value = bufnr,
    display = display,
    ordinal = bufnr,
  }
end

local function create_bare_buffer_previewer(title)
  return Previewer:new({
    setup = function()
      return {}
    end,
    teardown = function(self)
      if self.state and self.state.winid then
        -- https://github.com/nvim-telescope/telescope.nvim/blob/0c12735d5aff6a48ffd8111bf144dc2ff44e5975/lua/telescope/previewers/buffer_previewer.lua#L396
        -- push a new empty buffer because telescope deletes the last buffer
        local bufnr = vim.api.nvim_create_buf(false, true)
        utils.win_set_buf_noautocmd(self.state.winid, bufnr)
      end
    end,
    preview_fn = function(self, entry, status)
      local preview_winid = status.layout.preview
        and status.layout.preview.winid

      vim.api.nvim_win_set_buf(preview_winid, entry.value)
      self.state.winid = preview_winid
    end,
    title = title,
  })
end

local function mchat(opts)
  opts = opts or {}

  pickers
    .new(opts, {
      prompt_title = 'Name',
      finder = finders.new_table({
        results = get_mchat_buffers(),
        entry_maker = entry_maker,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          vim.api.nvim_set_current_buf(selection.value)
        end)
        return true
      end,
      previewer = create_bare_buffer_previewer('model.nvim mchat buffers'),
    })
    :find()
end

return require('telescope').register_extension({
  exports = {
    mchat = mchat,
  },
})
