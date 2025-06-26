if bufname('%') ==? 'llmchat'
    nnoremap <buffer> <silent> <CR> :LLMChat<CR>
    nnoremap <buffer> <silent> <C-c> :LLMCancel<CR>
endif
