## hugging face local provider
Consumes python files, uses StreamHandler to handle output

## Buffer mode
Response goes to a temporary buffer

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

## Can check the prompt of each response segment. Prompt shows in a float.

## see history of prompts and responses

## reorganize commands
