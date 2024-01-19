describe('server-sent events client', function()
  local sse = require('model.util.sse')

  local sse_client = function()
    local results = {}

    local client = sse.client({
      on_message = function(msg)
        results.messages = results.messages or {}
        table.insert(results.messages, msg)
      end,
      on_other = function(x)
        results.others = results.others or {}
        table.insert(results.others, x)
      end,
      on_error = function(err)
        results.errors = results.errors or {}
        table.insert(results.errors, err)
      end,
    })

    return {
      client = client,
      results = results,
    }
  end

  describe('client', function()
    it('calls on_message as messages arrive', function()
      local sse = sse_client()

      sse.client.on_stdout('data: boop\n')
      assert.are.same({}, sse.results) -- no \n\n yet so we haven't gotten a full message

      sse.client.on_stdout('data: beep\n\n')
      assert.are.same(
        { messages = {
          { data = 'boop\nbeep' },
        } },
        sse.results
      )

      sse.client.on_stdout('data: foo') -- \n\n not necessary for the last message
      sse.client.on_exit()

      assert.are.same({
        messages = {
          { data = 'boop\nbeep' },
          { data = 'foo' },
        },
      }, sse.results)
    end)

    it('calls on_other only after on_exit', function()
      local sse = sse_client()

      sse.client.on_stdout('foo')
      assert.are.same({}, sse.results)

      sse.client.on_stdout('bar\n\n')
      assert.are.same({}, sse.results)

      sse.client.on_exit()

      assert.are.same({ others = {
        'foobar\n\n',
      } }, sse.results)
    end)
  end)

  describe('client parses', function()
    local client_parse_expect = function(expected, outputs)
      local sse = sse_client()

      for _, out in ipairs(outputs) do
        sse.client.on_stdout(out)
      end

      sse.client.on_exit()

      assert.are.same(expected, sse.results)
    end

    it('partial not sse', function()
      client_parse_expect({
        others = { 'foobar' },
      }, {
        'foo',
        'bar',
      })
    end)
    it('complete not sse', function()
      client_parse_expect({
        others = { 'foobar' },
      }, {
        'foobar',
      })
    end)
    it('partial sse', function()
      client_parse_expect({
        messages = { { data = 'foobar' } },
      }, {
        'data: foo',
        'bar',
      })
    end)
    it('complete sse', function()
      client_parse_expect({
        messages = { { data = 'foobar' } },
      }, {
        'data: foobar',
      })
    end)
    it('partial multiple sse', function()
      client_parse_expect({
        messages = { { data = 'foobar\nbaz' } },
      }, {
        'data: foo',
        'bar\ndata: baz',
      })
    end)
    it('complete multiple sse', function()
      client_parse_expect({
        messages = { { data = 'foo\nbar' } },
      }, {
        'data: foo\ndata: bar',
      })
    end)
  end)
end)
