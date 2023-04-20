## builders can define a handler, on_partial, on_finish, on_error

## hugging face local provider
Consumes python files, uses StreamHandler to handle output

## add to context
`:LlmCtx add` - add additional selections as context for following calls

`:LLmCtx clear` - remove all ctx

`:LlmCtx show` - show included context (eventually qflist?)

`ctx.filename : string`  
`ctx.selections : string []`  

```lua
builder = function(input, ctx)
 ...
 vim.tbl_concat(ctx.selections, '\n\n')
 ...
end
```

## segment contains original prompt.builder result
`:LlmCheckPrompt`

## save a log of all prompt/response pairs so can traverse back and pull out responses

## reorganize commands
