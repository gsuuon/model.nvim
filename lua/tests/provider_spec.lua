local mock = require('luassert.mock')
local match = require('luassert.match')

local u = require('tests.util')
require('tests.matchers')

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
        local delay = 10
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
end)
