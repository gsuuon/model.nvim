if exists("b:current_syntax")
    finish
endif

syn include @Yaml syntax/yaml.vim

let b:current_syntax = 1

syntax match llmMessageSystem "> .*$" contained
syntax match llmMessageSystem /\%^> .*$/
syn region llmParams start=/\%^---$/ end="^---$" nextgroup=llmMessageSystem skipnl contains=@Yaml keepend
syn region llmMessageAssistant start="======" end="======"

hi link llmMessageAssistant Comment
hi link llmMessageSystem WarningMsg
