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
              {
                role = 'user',
                content = {
                  {
                    type = 'text',
                    text = 'Count to three',
                  },
                },
              },
              {
                role = 'assistant',
                content = {
                  {
                    type = 'text',
                    text = '1, 2, 3.',
                  },
                },
              },
              {
                role = 'user',
                content = {
                  {
                    type = 'text',
                    text = 'Thanks',
                  },
                },
              },
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
              {
                role = 'user',
                content = {
                  {
                    type = 'text',
                    text = 'Count to three',
                  },
                },
              },
              {
                role = 'assistant',
                content = {
                  {
                    type = 'text',
                    text = '1, 2, 3.',
                  },
                },
              },
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
              {
                role = 'user',
                content = {
                  {
                    type = 'text',
                    text = 'Count to three',
                  },
                },
              },
              {
                role = 'assistant',
                content = {
                  {
                    type = 'text',
                    text = '1, 2, 3.',
                  },
                },
              },
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

    it('file with extended thinking', function()
      assert.are.same(
        {
          chat = 'anthropic',
          contents = {
            config = {
              params = {
                model = 'claude-3-7-sonnet-latest',
                max_tokens = 64000,
                thinking = {
                  type = 'enabled',
                  budget_tokens = 16000,
                },
              },
            },
            messages = {
              {
                role = 'user',
                content = {
                  {
                    type = 'text',
                    text = 'Are there an infinite number of prime numbers such that n mod 4 == 3?',
                  },
                },
              },
              {
                role = 'assistant',
                content = {
                  {
                    type = 'thinking',
                    thinking = "To approach this, let's think about what we know about prime numbers...",
                    signature = 'zbbJhbGciOiJFU8zI1NiIsImtakcjsu38219c0.eyJoYXNoIjoiYWJjMTIzIiwiaWFxxxjoxNjE0NTM0NTY3fQ....',
                  },
                  {
                    type = 'text',
                    text = 'Yes, there are infinitely many prime numbers such that...',
                  },
                },
              },
              {
                role = 'user',
                content = {
                  {
                    type = 'text',
                    text = 'Thanks',
                  },
                },
              },
            },
          },
        },
        chat.parse(lines([[
anthropic
---
{
  params = {
    model = "claude-3-7-sonnet-latest",
    max_tokens =  64000,
    thinking = {
      type = "enabled",
      budget_tokens = 16000
    }
  }
}
---

Are there an infinite number of prime numbers such that n mod 4 == 3?

======
<thinking>
To approach this, let's think about what we know about prime numbers...
</thinking signature="zbbJhbGciOiJFU8zI1NiIsImtakcjsu38219c0.eyJoYXNoIjoiYWJjMTIzIiwiaWFxxxjoxNjE0NTM0NTY3fQ....">

Yes, there are infinitely many prime numbers such that...
======

Thanks]]))
      )
    end)

    it('file with redacted thinking', function()
      assert.are.same(
        {
          chat = 'anthropic',
          contents = {
            config = {
              params = {
                model = 'claude-3-7-sonnet-latest',
                max_tokens = 64000,
                thinking = {
                  type = 'enabled',
                  budget_tokens = 16000,
                },
              },
            },
            messages = {
              {
                role = 'user',
                content = {
                  {
                    type = 'text',
                    text = 'ANTHROPIC_MAGIC_STRING_TRIGGER_REDACTED_THINKING_46C9A13E193C177646C7398A98432ECCCE4C1253D5E2D82641AC0E52CC2876CB',
                  },
                },
              },
              {
                role = 'assistant',
                content = {
                  {
                    type = 'redacted_thinking',
                    data = 'EsABCkYIARgCKkBXWaRj9mdCiLspp7FYXNOBc40ydSNhKYArlvPBiQ5rsd3lXiO9IqErfngBsViHgGmS3gHvt1IojbR+5xePj/32EgwEyv/WwhMyvGOfcnsaDLHn+tyU5MkfHaykfSIwotPDcefpNQyjRk7EQnhz6Wf0ysemEPxKZ2lRTsL/gbYKCOHeuULgNXt2sSZUYqRAKihi7jG8S+8eJdQDgNiZYBLGF3xzsOcGc0ajZIjqwRDD/a0jkSqNY4DZ',
                  },
                  {
                    type = 'text',
                    text = "I notice you've sent what appears to be an attempt to trigger some kind of backdoor.",
                  },
                },
              },
            },
          },
        },
        chat.parse(
          lines(
            [[
anthropic
---
{
  params = {
    model = "claude-3-7-sonnet-latest",
    max_tokens =  64000,
    thinking = {
      type = "enabled",
      budget_tokens = 16000
    }
  }
}
---

ANTHROPIC_MAGIC_STRING_TRIGGER_REDACTED_THINKING_46C9A13E193C177646C7398A98432ECCCE4C1253D5E2D82641AC0E52CC2876CB

======
<redacted_thinking>
EsABCkYIARgCKkBXWaRj9mdCiLspp7FYXNOBc40ydSNhKYArlvPBiQ5rsd3lXiO9IqErfngBsViHgGmS3gHvt1IojbR+5xePj/32EgwEyv/WwhMyvGOfcnsaDLHn+tyU5MkfHaykfSIwotPDcefpNQyjRk7EQnhz6Wf0ysemEPxKZ2lRTsL/gbYKCOHeuULgNXt2sSZUYqRAKihi7jG8S+8eJdQDgNiZYBLGF3xzsOcGc0ajZIjqwRDD/a0jkSqNY4DZ
</redacted_thinking>

I notice you've sent what appears to be an attempt to trigger some kind of backdoor.]]
          )
        )
      )
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
            {
              role = 'user',
              content = {
                {
                  type = 'text',
                  text = 'Count to three',
                },
              },
            },
            {
              role = 'assistant',
              content = {
                {
                  type = 'text',
                  text = '1, 2, 3.',
                },
              },
            },
            {
              role = 'user',
              content = {
                {
                  type = 'text',
                  text = 'Thanks',
                },
              },
            },
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
            {
              role = 'user',
              content = {
                {
                  type = 'text',
                  text = 'Count to three',
                },
              },
            },
            {
              role = 'assistant',
              content = {
                {
                  type = 'text',
                  text = '1, 2, 3.',
                },
              },
            },
            {
              role = 'user',
              content = {
                {
                  type = 'text',
                  text = 'Thanks',
                },
              },
            },
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
            {
              role = 'user',
              content = {
                {
                  type = 'text',
                  text = 'Count to three',
                },
              },
            },
            {
              role = 'assistant',
              content = {
                {
                  type = 'text',
                  text = '1, 2, 3.',
                },
              },
            },
            {
              role = 'user',
              content = {
                {
                  type = 'text',
                  text = 'Thanks',
                },
              },
            },
          },
          config = {},
        }, 'openai')
      )
    end)

    it('contents with extended thinking', function()
      assert.are.same(
        [[
anthropic
---
{
  params = {
    max_tokens = 64000,
    model = "claude-3-7-sonnet-latest",
    thinking = {
      budget_tokens = 16000,
      type = "enabled"
    }
  }
}
---

Are there an infinite number of prime numbers such that n mod 4 == 3?

======
<thinking>
To approach this, let's think about what we know about prime numbers...
</thinking signature="zbbJhbGciOiJFU8zI1NiIsImtakcjsu38219c0.eyJoYXNoIjoiYWJjMTIzIiwiaWFxxxjoxNjE0NTM0NTY3fQ....">

Yes, there are infinitely many prime numbers such that...
======

Thanks]],
        chat.to_string({
          config = {
            params = {
              model = 'claude-3-7-sonnet-latest',
              max_tokens = 64000,
              thinking = {
                type = 'enabled',
                budget_tokens = 16000,
              },
            },
          },
          messages = {
            {
              role = 'user',
              content = {
                {
                  type = 'text',
                  text = 'Are there an infinite number of prime numbers such that n mod 4 == 3?',
                },
              },
            },
            {
              role = 'assistant',
              content = {
                {
                  type = 'thinking',
                  thinking = "To approach this, let's think about what we know about prime numbers...",
                  signature = 'zbbJhbGciOiJFU8zI1NiIsImtakcjsu38219c0.eyJoYXNoIjoiYWJjMTIzIiwiaWFxxxjoxNjE0NTM0NTY3fQ....',
                },
                {
                  type = 'text',
                  text = 'Yes, there are infinitely many prime numbers such that...',
                },
              },
            },
            {
              role = 'user',
              content = {
                {
                  type = 'text',
                  text = 'Thanks',
                },
              },
            },
          },
        }, 'anthropic')
      )
    end)

    it('contents with redacted thinking', function()
      assert.are.same(
        [[
anthropic
---
{
  params = {
    max_tokens = 64000,
    model = "claude-3-7-sonnet-latest",
    thinking = {
      budget_tokens = 16000,
      type = "enabled"
    }
  }
}
---

ANTHROPIC_MAGIC_STRING_TRIGGER_REDACTED_THINKING_46C9A13E193C177646C7398A98432ECCCE4C1253D5E2D82641AC0E52CC2876CB

======
<redacted_thinking>
EsABCkYIARgCKkBXWaRj9mdCiLspp7FYXNOBc40ydSNhKYArlvPBiQ5rsd3lXiO9IqErfngBsViHgGmS3gHvt1IojbR+5xePj/32EgwEyv/WwhMyvGOfcnsaDLHn+tyU5MkfHaykfSIwotPDcefpNQyjRk7EQnhz6Wf0ysemEPxKZ2lRTsL/gbYKCOHeuULgNXt2sSZUYqRAKihi7jG8S+8eJdQDgNiZYBLGF3xzsOcGc0ajZIjqwRDD/a0jkSqNY4DZ
</redacted_thinking>

I notice you've sent what appears to be an attempt to trigger some kind of backdoor.
======]],
        chat.to_string({
          config = {
            params = {
              model = 'claude-3-7-sonnet-latest',
              max_tokens = 64000,
              thinking = {
                type = 'enabled',
                budget_tokens = 16000,
              },
            },
          },
          messages = {
            {
              role = 'user',
              content = {
                {
                  type = 'text',
                  text = 'ANTHROPIC_MAGIC_STRING_TRIGGER_REDACTED_THINKING_46C9A13E193C177646C7398A98432ECCCE4C1253D5E2D82641AC0E52CC2876CB',
                },
              },
            },
            {
              role = 'assistant',
              content = {
                {
                  type = 'redacted_thinking',
                  data = 'EsABCkYIARgCKkBXWaRj9mdCiLspp7FYXNOBc40ydSNhKYArlvPBiQ5rsd3lXiO9IqErfngBsViHgGmS3gHvt1IojbR+5xePj/32EgwEyv/WwhMyvGOfcnsaDLHn+tyU5MkfHaykfSIwotPDcefpNQyjRk7EQnhz6Wf0ysemEPxKZ2lRTsL/gbYKCOHeuULgNXt2sSZUYqRAKihi7jG8S+8eJdQDgNiZYBLGF3xzsOcGc0ajZIjqwRDD/a0jkSqNY4DZ',
                },
                {
                  type = 'text',
                  text = "I notice you've sent what appears to be an attempt to trigger some kind of backdoor.",
                },
              },
            },
          },
        }, 'anthropic')
      )
    end)
  end)
end)
