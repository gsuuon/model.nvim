local mock = require('luassert.mock')
local match = require('luassert.match')

describe('setup', function()

  local test_provider = mock({ request_completion = function() end })

  require('llm').setup({
    default_prompt = {
      provider = test_provider,
      builder = function()
        return { param = 'default' }
      end
    },
    prompts = {
      foo = {
        provider = test_provider,
        builder = function()
          return { param = 'foo' }
        end
      },
      bar = {
        provider = test_provider,
        builder = function()
          return { param = 'bar' }
        end
      }
    }
  })

  it('takes a default prompt', function()

    vim.cmd('Llm')

    assert.spy(test_provider.request_completion).was_called_with(
      match.is_table(),
      { param = 'default' },
      nil
    )
  end)

  it('takes prompts', function()

    vim.cmd('Llm foo')

    assert.spy(test_provider.request_completion).was_called_with(
      match.is_table(),
      { param = 'foo' },
      nil
    )

    vim.cmd('Llm bar')

    assert.spy(test_provider.request_completion).was_called_with(
      match.is_table(),
      { param = 'bar' },
      nil
    )
  end)

  it('errors if trying to call missing prompt', function()

    assert.has.errors(function()
      vim.cmd('Llm boopity')
    end)

  end)
end)
