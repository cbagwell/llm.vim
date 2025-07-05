" llm.vim - AI Assistant for Vim using llm cli

command! -range -nargs=* LLMChat <line1>,<line2>call llm#LLMChat(<f-args>)
command! LLMCancel call llm#LLMCancel()
command! LLMIsRunning echo llm#LLMIsRunning()

command! -range LLMDoc <line1>,<line2>call llm#LLMDoc()
command! -range LLMFix <line1>,<line2>call llm#LLMFix()
command! -range -nargs=* LLMComplete <line1>,<line2>call llm#LLMComplete(<q-args>)
command! -range -nargs=+ LLMFilter <line1>,<line2>Lcall llm#LLMFilter(<q-args>)
command! -nargs=+ LLMRead call append(line('.'), llm#LLMRead(expand("<args>")))
