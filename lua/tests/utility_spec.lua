local u = require('tests.util')

describe('cursor.selection', function()

  it('gets 0-indexed cursor position', function()

    local util = require('llm.util')

    local buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_win_set_buf(0, buf)
    u.type_keys('iabc<C-c>V<esc>') -- select first line, then exit to normal mode to update < and > marks

    local selection = util.cursor.selection()

    assert.are.same({
      start = {
        row = 0,
        col = 0
      },
      stop = {
        row = 0,
        col = vim.v.maxcol
      }
    }, selection)

  end)
end)
