local mock = require('luassert.mock')
local match = require('luassert.match')

require('tests.matchers')
local u = require('tests.util')

describe('prompt', function()

  local provider = require('llm.core.provider')
  local test_provider = mock({ request_completion = function() end })

  it('provides builder with input and context', function()

    local buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, {'abc', 'def'})
    u.type_keys('ggV<esc>')

    local prompt = mock({
      provider = test_provider,
      builder = function() return { paramA = true } end
    })

    provider.request_completion(prompt, '', true)

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

  it('errors if builder returns nil', function()

    assert.has.errors(function()
      provider.request_completion({
        provider = test_provider,
        builder = function() end
      }, '', true)
    end)

  end)

  it('can return a function as builder', function()

    provider.request_completion({
      provider = test_provider,
      builder = function()
        return function(build)
          build({
            paramAFunc = true
          })
        end
      end
    }, '', true)

    assert.spy(test_provider.request_completion).was_called_with(
      match.table_types({
        on_finish = 'function',
        on_partial = 'function',
        on_error = 'function',
      }),
      { paramAFunc = true },
      nil
    )
  end)

end)
