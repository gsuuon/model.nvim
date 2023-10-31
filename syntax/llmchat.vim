if exists("b:current_syntax")
    finish
endif

let b:current_syntax = 1

syntax match llmMessageSystem "^> .*$" contained

syn region llmMessageAssistant start="======" end="======"
syn region firstLine start=/\%^/ end="\n" contains=llmMessageSystem

hi link llmMessageAssistant Comment
hi link llmMessageSystem WarningMsg
