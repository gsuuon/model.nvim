local chat = require('llm.core.chat')

describe('chat', function()
  describe('parse', function()
    it('file with name, config, system, and messages', function()
      assert.are.same(
        {
          chat = 'openai',
          contents = {
            config = {
              model = 'gpt-3.5-turbo'
            },
            system = 'You are a helpful assistant',
            messages = {
              { role = 'user', content = 'Count to three' },
              { role = 'assistant', content = '1, 2, 3.' },
              { role = 'user', content = 'Thanks' },
            }
          }
        },
        chat.parse([[
openai
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

Thanks]])
      )
    end)

    it('file with system, and messages', function()
      assert.are.same(
        {
          chat = 'openai',
          contents = 
            {
              system = 'You are a helpful assistant',
              messages = {
                { role = 'user', content = 'Count to three' },
                { role = 'assistant', content = '1, 2, 3.' }
              }
            }
        },
        chat.parse([[
openai
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
          chat = 'openai',
          contents = 
            {
              messages = {
                { role = 'user', content = 'Count to three' },
                { role = 'assistant', content = '1, 2, 3.' }
              },
            }
        },
        chat.parse([[
openai

Count to three

======
1, 2, 3.
======
]])
      )
    end)

    it('file with config', function()
      assert.are.same(
        {
          chat = 'openai',
          contents =
            {
              config = {
                model = 'gpt-3.5-turbo'
              },
              messages = {}
            }
        },
        chat.parse([[
openai
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
          chat = 'openai',
          contents = {
            system = 'You are a helpful assistant',
            messages = {}
          }
        },
        chat.parse([[openai
> You are a helpful assistant
]])
      )
    end)

    it('file with no chat name', function()
      assert.has.errors(function()
        chat.parse([[
> You are a helpful assistant
]])
      end)
    end)
  end)

  describe('to string', function()
    it('contents with config, system and messages', function()
      assert.are.same(
        [[
openai
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

Thanks]],
        chat.to_string(
          {
            config = {
              model = 'gpt-3.5-turbo'
            },
            system = 'You are a helpful assistant',
            messages = {
              { role = 'user', content = 'Count to three' },
              { role = 'assistant', content = '1, 2, 3.' },
              { role = 'user', content = 'Thanks' },
            },
          },
          'openai'
        )
      )
    end)

    it('contents with system and messages', function()
      assert.are.same(
        [[
openai
> You are a helpful assistant

Count to three

======
1, 2, 3.
======

Thanks]],
        chat.to_string(
          {
            system = 'You are a helpful assistant',
            messages = {
              { role = 'user', content = 'Count to three' },
              { role = 'assistant', content = '1, 2, 3.' },
              { role = 'user', content = 'Thanks' },
            },
          },
          'openai'
        )
      )
    end)

    it('contents with messages', function()
      assert.are.same(
        [[openai

Count to three

======
1, 2, 3.
======

Thanks]],
        chat.to_string(
          {
            messages = {
              { role = 'user', content = 'Count to three' },
              { role = 'assistant', content = '1, 2, 3.' },
              { role = 'user', content = 'Thanks' },
            },
          },
          'openai'
        )
      )
    end)
  end)
end)

