local mock = require('luassert.mock')
local match = require('luassert.match')

local u = require('tests.util')
require('tests.matchers')

local delay = 10

local type_stream_handlers = {
  on_finish = 'function',
  on_partial = 'function',
  on_error = 'function'
}

describe('provider', function()
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
    u.type_keys('ggV<esc>')

    local test_provider = { request_completion = function() end }
    local prompt = mock({
      provider = test_provider,
      builder = function() return { paramA = true } end
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

  it('streams in partials and finishes with prompt transform', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buf)
    assert.are.same({''}, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    local co = coroutine.running()

    local test_provider = {
      request_completion = function(handlers)
        local lines = { 'foo', 'bar', 'baz' }

        for i,line in ipairs(lines) do
          vim.defer_fn(function()
            handlers.on_partial(line)
            coroutine.resume(co)
          end, i * delay)
        end

        vim.defer_fn(function()
          handlers.on_finish(table.concat(lines, '\n'))
          coroutine.resume(co)
        end, (#lines + 1) * delay)

        vim.defer_fn(function() -- for the transform
          coroutine.resume(co)
        end, (#lines + 2) * delay)
      end,
    }

    provider.request_completion({
      provider = test_provider,
      builder = function() return {} end,
      transform = function(completion)
        return completion:gsub('ba', 'pa')
      end
    }, '', false)

    coroutine.yield()
    assert.are.same({'', ''}, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

    coroutine.yield()
    assert.are.same({'', 'foo'}, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

    coroutine.yield()
    assert.are.same({'', 'foobar'}, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

    coroutine.yield()
    assert.are.same({'', 'foobarbaz'}, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

    coroutine.yield()
    assert.are.same({'', 'foo', 'par', 'paz'}, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it('calls custom mode stream handlers', function()
    local co = coroutine.running()

    local test_provider = {
      request_completion = function(handlers)

        vim.defer_fn(function ()
          handlers.on_partial('partial')
          coroutine.resume(co)
        end, delay)

        vim.defer_fn(function ()
          handlers.on_finish('finish')
          coroutine.resume(co)
        end, delay * 2)

        vim.defer_fn(function ()
          handlers.on_error('error')
          coroutine.resume(co)
        end, delay * 3)
      end
    }

    local noop = function() end

    local custom_mode = mock({
      on_finish = noop,
      on_partial = noop,
      on_error = noop,
    })

    provider.request_completion({
      provider = test_provider,
      builder = function() return {} end,
      mode = custom_mode
    }, '', false)

    assert.spy(custom_mode.on_partial).was_not_called()
    assert.spy(custom_mode.on_finish).was_not_called()
    coroutine.yield()

    assert.spy(custom_mode.on_partial).was_called_with('partial')
    assert.spy(custom_mode.on_finish).was_not_called()

    coroutine.yield()
    assert.spy(custom_mode.on_finish).was_called_with('finish')

    coroutine.yield()
    assert.spy(custom_mode.on_error).was_called_with('error')
  end)
end)
