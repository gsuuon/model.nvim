local util = require('model.util')

local function context_string(context, filetype)
  return string.format(
    [[
File: %s

Before (0,0)-%s:
```%s
%s
```

After %s-%s:
```%s
%s
```
              ]],
    context.filename,
    util.position_string(context.before_range.stop),
    filetype,
    context.before,
    util.position_string(context.after_range.start),
    util.position_string(context.after_range.stop),
    filetype,
    context.after
  )
end

local function build_replace(input, context)
  local filetype = vim.filetype.match({ buf = 0 })

  local selected_range_text = string.format(
    '%s-%s',
    util.position_string((context.selection or {}).start or context.position),
    util.position_string((context.selection or {}).stop or context.position)
  )

  local prompt = context_string(context, filetype)
    .. string.format(
      [[
Selected %s:
```%s
%s
```

Instructions:
%s
              ]],
      selected_range_text,
      filetype,
      input,
      context.args or 'Generate code which goes between Before and After'
    )

  local result = {
    messages = {
      {
        role = 'user',
        content = prompt,
      },
      {
        role = 'assistant',
        content = string.format(
          [[
Replace selected %s:
```%s]],
          selected_range_text,
          filetype
        ),
      },
    },
  }

  return result
end

local function build_insert(context)
  local filetype = vim.filetype.match({ buf = 0 })

  local insert_position = string.format(
    '%s-%s',

    util.position_string(context.position),
    util.position_string(context.position)
  )

  local prompt = context_string(context, filetype)
    .. string.format(
      [[
Instructions:
%s
              ]],
      context.args or 'Generate code which goes between Before and After'
    )

  local result = {
    messages = {
      {
        role = 'user',
        content = prompt,
      },
      {
        role = 'assistant',
        content = string.format(
          [[
Insert at %s:
```%s]],
          insert_position,
          filetype
        ),
      },
    },
  }

  return result
end

return {
  build_replace = build_replace,
  build_insert = build_insert,
}
