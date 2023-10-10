local mock = require('luassert.mock')
local match = require('luassert.match')

require('tests.matchers')

local function type_keys(keys, flags)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), flags or 'x', false)
end

local type_stream_handlers = {
  on_finish = 'function',
  on_partial = 'function',
  on_error = 'function'
}

describe('nvim api and utilities', function()
  describe('cursor.selection', function()
    it('gets 0-indexed cursor position', function()
      local util = require('llm.util')

      local buf = vim.api.nvim_create_buf(false, true)

      vim.api.nvim_win_set_buf(0, buf)
      type_keys('iabc<C-c>V<esc>') -- select first line, then exit to normal mode to update < and > marks

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
end)

describe('llm.provider', function()
  local provider = require('llm.provider')

  it('calls the prompt provider completion with params and options', function()
    local test_provider = mock({ request_completion = function() end })

    provider.request_completion({
      provider = test_provider,
      options = { optA = true },
      builder = function() return { paramA = true } end
    }, '', false, 'Comment')

    assert.spy(test_provider.request_completion).was_called_with(
      match.table_types(type_stream_handlers),
      { paramA = true },
      { optA = true }
    )

    provider.request_completion({
      provider = test_provider,
      builder = function() return { paramA = true } end
    }, '', false, 'Comment')

    assert.spy(test_provider.request_completion).was_called_with(
      match.table_types(type_stream_handlers),
      { paramA = true },
      nil
    )
  end)

  it('calls the prompt builder with input and context', function()
    local buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, {'abc', 'def'})
    type_keys('ggV<esc>')

    local test_provider = { request_completion = function() end }
    local prompt = mock({
      provider = test_provider,
      builder = function(input, context)
        print(vim.inspect({input=input, context=context}))
        return { paramA = true }
      end
    })

    provider.request_completion(prompt, '', true, 'Comment')

    assert.spy(prompt.builder).was_called_with(
      'abc',
      match.table_types({
        before = 'table',
        after = 'table',
        args = 'string',
        filename = 'string',
        selection = {
          start = {
            col = 'number',
            row = 'number',
          },
          stop = {
            col = 'number',
            row = 'number',
          },
        },
      })
    )
  end)
end)
