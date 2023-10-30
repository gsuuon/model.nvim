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

describe('server-sent events iterator', function()
  local p_util = require('llm.providers.util')

  local function parse_expect_sse(outputs, expected)
    local got = {}

    local parse = p_util.iter_sse_messages(function(event)
      table.insert(got, event)
    end)

    for _,output in ipairs(outputs) do
      parse(output)
    end

    assert.are.same(expected, got)
  end

  it('parses single message output', function()

    parse_expect_sse(
      {
        'data: {"a": true}\n\n',
        'data: {"b": false}\n\n',
      },
      {
        { data = '{"a": true}' },
        { data = '{"b": false}' }
      }
    )

  end)

  it('parses multiple message outputs', function()

    parse_expect_sse(
      {
        'data: {"a": true}\n\ndata: {"b": false}\n\n',
        'data: {"c": true}\n\ndata: {"d": false}\n\n',
      },
      {
        { data = '{"a": true}' },
        { data = '{"b": false}' },
        { data = '{"c": true}' },
        { data = '{"d": false}' }
      }
    )

  end)

  it('parses partial message outputs', function()

    parse_expect_sse(
      {
        'data: {"a": true,',
        'data: "b": false}\n\n',
        'data: {"c": true,',
        'data: "d": false}\n\n',
      },
      {
        { data = '{"a": true,\n"b": false}' },
        { data = '{"c": true,\n"d": false}' }
      }
    )
  end)

  describe('data helper', function()
    local function parse_expect_data(outputs, expected)
      local got = {}

      local parse = p_util.iter_sse_data(function(event)
        table.insert(got, event)
      end)

      for _,output in ipairs(outputs) do
        parse(output)
      end

      assert.are.same(expected, got)
    end

    it('parses out data values', function()

      parse_expect_data(
        {
          'data: {"a": true}\n\ndata: {"b": false}\n\n',
          'data: {"c": true}\n\ndata: {"d": false}\n\n',
        },
        {
          '{"a": true}',
          '{"b": false}',
          '{"c": true}',
          '{"d": false}'
        }
      )

    end)
  end)
end)
