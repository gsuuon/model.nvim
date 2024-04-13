if exists("b:current_syntax")
    finish
endif

syn include @Lua syntax/lua.vim

let b:current_syntax = 1

lua << EOF
local ok, parsers = pcall(require, "nvim-treesitter.parsers")
if ok then
  if not parsers.has_parser() then
    vim.opt_local.foldmethod = 'syntax'
  end
end
EOF

syn sync fromstart

syn match modelChatName /\%^\(---\)\@!.\+/ skipnl nextgroup=modelChatMessageSystem,modelChatParams,modelChatMessages
syn region modelChatParams start=/^---$/ end=/^---$/ nextgroup=modelChatMessageSystem,modelChatMessages skipnl contains=@Lua keepend contained fold
syn region modelChatMessages start=/^\(---\)\@!.*/ end=/\%$/ contains=modelChatMessageAssistant contained
syn match modelChatMessageSystem "^> .*$" nextgroup=modelChatMessages skipempty contained
syn region modelChatMessageAssistant start=/^======$/ end=/^======$/ contained fold

hi link modelChatName ModeMsg
hi link modelChatMessageAssistant Identifier
hi link modelChatMessageSystem WarningMsg
