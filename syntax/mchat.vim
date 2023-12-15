if exists("b:current_syntax")
    finish
endif

syn include @Lua syntax/lua.vim

let b:current_syntax = 1

setlocal foldmethod=syntax
syn sync fromstart

syn match modelChatName /\%^\(---\)\@!.\+/ skipnl nextgroup=modelChatMessageSystem,modelChatParams,modelChatMessages
syn region modelChatParams start=/^---$/ end=/^---$/ nextgroup=modelChatMessageSystem,modelChatMessages skipnl contains=@Lua keepend contained fold
syn region modelChatMessages start=/^\(---\)\@!.*/ end=/\%$/ contains=modelChatMessageAssistant contained
syn match modelChatMessageSystem "^> .*$" nextgroup=modelChatMessages skipempty contained
syn region modelChatMessageAssistant start=/^======$/ end=/^======$/ contained fold

hi link modelChatName ModeMsg
hi link modelChatMessageAssistant Identifier
hi link modelChatMessageSystem WarningMsg
