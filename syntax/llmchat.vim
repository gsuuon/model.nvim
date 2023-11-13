if exists("b:current_syntax")
    finish
endif

syn include @Lua syntax/lua.vim

let b:current_syntax = 1

syn match llmChatName /\%^\(---\)\@!.\+/ skipnl nextgroup=llmMessageSystem,llmParams,llmMessages
syn region llmParams start=/^---$/ end=/^---$/ nextgroup=llmMessageSystem,llmMessages skipnl contains=@Lua keepend contained
syn region llmMessages start=/^\(---\)\@!.\+/ end=/\%$/ contains=llmMessageAssistant contained
syn match llmMessageSystem "^> .*$" nextgroup=llmMessages skipempty contained
syn region llmMessageAssistant start="======" end="======" contained

hi link llmChatName ModeMsg
hi link llmMessageAssistant Identifier
hi link llmMessageSystem WarningMsg
