local chat = require('llm.chat')

describe('chat', function()
  describe('parse', function()
    it('file with params, system, and messages', function()
      assert.are.same(
        {
          params = {
            model = 'gpt-3.5-turbo'
          },
          system = 'You are a helpful assistant',
          messages = {
            { role = 'user', content = 'Count to three' },
            { role = 'assistant', content = '1, 2, 3.' },
            { role = 'user', content = 'Thanks' },
          }
        },
        chat.parse([[
---
{
  model = "gpt-3.5-turbo"
}
---
> You are a helpful assistant

Count to three

======
1, 2, 3.
======

Thanks
]])
      )
    end)

    it('file with system, and messages', function()
      assert.are.same(
        {
          system = 'You are a helpful assistant',
          params = {},
          messages = {
            { role = 'user', content = 'Count to three' },
            { role = 'assistant', content = '1, 2, 3.' }
          }
        },
        chat.parse([[
> You are a helpful assistant

Count to three

======
1, 2, 3.
======
]])
      )
    end)

    it('file with messages', function()
      assert.are.same(
        {
          messages = {
            { role = 'user', content = 'Count to three' },
            { role = 'assistant', content = '1, 2, 3.' }
          },
          params = {},
        },
        chat.parse([[
Count to three

======
1, 2, 3.
======
]])
      )
    end)

    it('file with params', function()
      assert.are.same(
        {
          params = {
            model = 'gpt-3.5-turbo'
          },
          messages = {}
        },
        chat.parse([[
---
{
  model = "gpt-3.5-turbo"
}
---
]])
      )
    end)

    it('file with system', function()
      assert.are.same(
        {
          system = 'You are a helpful assistant',
          messages = {},
          params = {}
        },
        chat.parse([[
> You are a helpful assistant
]])
      )
    end)
  end)

  describe('to string', function()
    it('contents with params, system and messages', function()
      assert.are.same(
        [[---
{
  model = "gpt-3.5-turbo"
}
---
> You are a helpful assistant

Count to three

======
1, 2, 3.
======

Thanks
]],
        chat.to_string({
          params = {
            model = 'gpt-3.5-turbo'
          },
          system = 'You are a helpful assistant',
          messages = {
            { role = 'user', content = 'Count to three' },
            { role = 'assistant', content = '1, 2, 3.' },
            { role = 'user', content = 'Thanks' },
          }
        })
      )
    end)

    it('contents with system and messages', function()
      assert.are.same(
        [[> You are a helpful assistant

Count to three

======
1, 2, 3.
======

Thanks
]],
        chat.to_string({
          system = 'You are a helpful assistant',
          params = {},
          messages = {
            { role = 'user', content = 'Count to three' },
            { role = 'assistant', content = '1, 2, 3.' },
            { role = 'user', content = 'Thanks' },
          }
        })
      )
    end)

    it('contents with messages', function()
      assert.are.same(
        [[

Count to three

======
1, 2, 3.
======

Thanks
]],
        chat.to_string({
          messages = {
            { role = 'user', content = 'Count to three' },
            { role = 'assistant', content = '1, 2, 3.' },
            { role = 'user', content = 'Thanks' },
          },
          params = {}
        })
      )
    end)
  end)
end)

