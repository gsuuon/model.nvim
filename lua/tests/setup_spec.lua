local mock = require('luassert.mock')
local match = require('luassert.match')

describe('setup', function()
  local test_provider = mock({ request_completion = function() end })

  require('model').setup({
    default_prompt = {
      provider = test_provider,
      builder = function()
        return { param = 'default' }
      end,
    },
    prompts = {
      foo = {
        provider = test_provider,
        builder = function()
          return { param = 'foo' }
        end,
      },
      bar = {
        provider = test_provider,
        builder = function()
          return { param = 'bar' }
        end,
      },
    },
  })

  it('takes a default prompt', function()
    vim.cmd('Model')

    assert
      .spy(test_provider.request_completion)
      .was_called_with(match.is_table(), { param = 'default' }, nil)
  end)

  it('takes prompts', function()
    vim.cmd('Model foo')

    assert
      .spy(test_provider.request_completion)
      .was_called_with(match.is_table(), { param = 'foo' }, nil)

    vim.cmd('Model bar')

    assert
      .spy(test_provider.request_completion)
      .was_called_with(match.is_table(), { param = 'bar' }, nil)
  end)

  it('errors if trying to call missing prompt', function()
    assert.has.errors(function()
      vim.cmd('Model boopity')
    end)
  end)

  it('can merge opts which contain prompts', function()
    require('model').setup({
      default_prompt = require('model.providers.palm').default_prompt,
    })
  end)
end)
