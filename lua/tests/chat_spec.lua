local chat = require('model.core.chat')

local function lines(text)
  return vim.fn.split(text, '\n')
end

describe('chat', function()
  describe('parse', function()
    it('file with name, config, system, and messages', function()
      assert.are.same(
        {
          chat = 'openai',
          contents = {
            config = {
              params = {
                model = 'gpt-3.5-turbo',
              },
              system = 'You are a helpful assistant',
            },
            messages = {
              { role = 'user', content = 'Count to three' },
              { role = 'assistant', content = '1, 2, 3.' },
              { role = 'user', content = 'Thanks' },
            },
          },
        },
        chat.parse(lines([[
openai
---
{
  params = {
    model = "gpt-3.5-turbo"
  }
}
---
> You are a helpful assistant

Count to three

======
1, 2, 3.
======

Thanks]]))
      )
    end)

    it('file with system, and messages', function()
      assert.are.same(
        {
          chat = 'openai',
          contents = {
            config = {
              system = 'You are a helpful assistant',
            },
            messages = {
              { role = 'user', content = 'Count to three' },
              { role = 'assistant', content = '1, 2, 3.' },
            },
          },
        },
        chat.parse(lines([[
openai
> You are a helpful assistant

Count to three

======
1, 2, 3.
======
]]))
      )
    end)

    it('file with messages', function()
      assert.are.same(
        {
          chat = 'openai',
          contents = {
            config = {},
            messages = {
              { role = 'user', content = 'Count to three' },
              { role = 'assistant', content = '1, 2, 3.' },
            },
          },
        },
        chat.parse(lines([[
openai

Count to three

======
1, 2, 3.
======
]]))
      )
    end)

    it('file with config', function()
      assert.are.same(
        {
          chat = 'openai',
          contents = {
            config = {
              model = 'gpt-3.5-turbo',
            },
            messages = {},
          },
        },
        chat.parse(lines([[
openai
---
{
  model = "gpt-3.5-turbo"
}
---
]]))
      )
    end)

    it('file with system', function()
      assert.are.same(
        {
          chat = 'openai',
          contents = {
            config = {
              system = 'You are a helpful assistant',
            },
            messages = {},
          },
        },
        chat.parse(lines([[openai
> You are a helpful assistant
]]))
      )
    end)

    it('file with no chat name', function()
      assert.has.errors(function()
        chat.parse(lines([[
> You are a helpful assistant
]]))
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
        chat.to_string({
          config = {
            model = 'gpt-3.5-turbo',
            system = 'You are a helpful assistant',
          },
          messages = {
            { role = 'user', content = 'Count to three' },
            { role = 'assistant', content = '1, 2, 3.' },
            { role = 'user', content = 'Thanks' },
          },
        }, 'openai')
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
        chat.to_string({
          config = {
            system = 'You are a helpful assistant',
          },
          messages = {
            { role = 'user', content = 'Count to three' },
            { role = 'assistant', content = '1, 2, 3.' },
            { role = 'user', content = 'Thanks' },
          },
        }, 'openai')
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
        chat.to_string({
          messages = {
            { role = 'user', content = 'Count to three' },
            { role = 'assistant', content = '1, 2, 3.' },
            { role = 'user', content = 'Thanks' },
          },
          config = {},
        }, 'openai')
      )
    end)
  end)
end)
