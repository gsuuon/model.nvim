if exists("b:current_syntax")
    finish
endif

syn include @Json syntax/json.vim

let b:current_syntax = 1

syntax match llmMessageSystem "> .*$" contained
syntax match llmMessageSystem /\%^> .*$/
syn region llmParams start=/\%^---$/ end="^---$" nextgroup=llmMessageSystem skipnl contains=@Json keepend
syn region llmMessageAssistant start="======" end="======"

hi link llmMessageAssistant Comment
hi link llmMessageSystem WarningMsg
