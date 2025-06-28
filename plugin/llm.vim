" llm.vim - AI Assistant for Vim using llm cli

command! -range -nargs=* LLMChat <line1>,<line2>call llm#LLMChat(<f-args>)
command! LLMCancel call llm#LLMCancel()
command! LLMIsRunning echo llm#LLMIsRunning()

command! -range=% LLMFix call llm#LLMFix()
command! -range=% LLMComplete call llm#LLMComplete()
command! -range=% -nargs=+ LLMFilter call llm#LLMFilter(<q-args>)
command! -nargs=+ LLMRead call append(line('.'), llm#LLMRead(expand("<args>")))
