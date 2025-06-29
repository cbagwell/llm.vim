scriptencoding utf-8
" llm.vim - AI Assistant for Vim

" Default timeout for llm jobs in seconds (5 minutes)
let g:llm_timeout_seconds = get(g:, 'llm_timeout_seconds', 300)
" Default llm command (e.g., 'llm', '/usr/local/bin/llm', 'python -m llm')
let g:llm_command = get(g:, 'llm_command', 'llm')
" Enable/disable reporting of token usage
let g:llm_enable_usage = get(g:, 'llm_enable_usage', v:true)
" Configure how the llmchat buffer is opened: 'vertical', 'horizontal', or 'current'
let g:llm_chat_new_behavior = get(g:, 'llm_chat_new_behavior', 'vertical')
" Default llm model to use (e.g., 'gpt-4o', 'claude-3.5-sonnet').
" An empty string means no '-m' option is added.
let g:llm_model = get(g:, 'llm_model', '')
" Optional llm model temperature. An empty string means no '-o temperature' option is added.
let g:llm_model_temperature = get(g:, 'llm_model_temperature', '')
" Characters to use for the spinner
let g:llm_spinner_chars = get(g:, 'llm_spinner_chars', ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'])

function! llm#LLMChat(...) abort range
    " Store off any visual selection/range lines up front. Single
    " line ranges that are not visual selections are not supported.
    let l:pasted_prompt = []
    " Only paste prompt if not already in the llmchat buffer
    if bufnr('%') != bufnr('llmchat')
        if (a:firstline == line("'<") && a:lastline == line("'>")) || a:firstline != a:lastline
            let l:pasted_prompt = ['This text is from a vim editing session that reports the filetype as "' . &filetype . '".', '', '```' . &filetype ]
            call extend(l:pasted_prompt, getline(a:firstline, a:lastline))
            call extend(l:pasted_prompt, ['```'])
        endif
    endif

    call s:LLMChatOpenWin()

    " llmchat buffer immediately after opening/switching
    let l:llmchat_buffer_nr = bufnr('%')

    call s:DeleteEmptyPrompt(l:llmchat_buffer_nr)

    let l:should_call_llm = v:false

    " Make sure we know where cursor is before appending.
    normal! G

    if !empty(l:pasted_prompt)
        call appendbufline(l:llmchat_buffer_nr, '$', ['', '# >>> Pasted Prompt'])
        " Prevent empty line in empty buffers
        if line('$') == 3
            call deletebufline(l:llmchat_buffer_nr, 1)
        endif
        call appendbufline(l:llmchat_buffer_nr, '$', l:pasted_prompt)
        " Force markdown resync in case its a large paste
        syntax sync fromstart
    endif

    if a:0 > 0 " Prompt passed in to function
        call appendbufline(l:llmchat_buffer_nr, '$', ['# >>> User Prompt', join(a:000)])
        " Prevent empty line in empty buffers
        if line('$') == 3
            call deletebufline(l:llmchat_buffer_nr, 1)
        endif
        let l:should_call_llm = v:true
    else " No argument provided: check last header to decide action
        " Re-evaluate last header info after potential cleanup
        let l:last_header = s:GetLastPromptHeader(l:llmchat_buffer_nr)
        if l:last_header.type ==? 'User Prompt'
            " Last header is User Prompt, send the entire buffer as context
            let l:should_call_llm = v:true
        else
            " Last header is Assistant Response (or empty buffer),
            " add new User Prompt header but don't send yet
            if l:last_header.type !=? ''
                call appendbufline(l:llmchat_buffer_nr, '$', [''])
            endif
            call appendbufline(l:llmchat_buffer_nr, '$', ['# >>> User Prompt', ''])
            " Prevent empty line in empty buffers
            if line('$') == 3
                call deletebufline(l:llmchat_buffer_nr, 1)
            endif
            normal! G
        endif
    endif

    if l:should_call_llm
        " If a job is already running, cancel it first
        if llm#LLMIsRunning()
            call llm#LLMCancel()
        endif

        let l:lines_to_send = getbufline(l:llmchat_buffer_nr, 1, '$')

        " Add Assistant Response header before sending the prompt
        call appendbufline(l:llmchat_buffer_nr, '$', ['', '# <<< Assistant Response'])

        " Always go to the end of the buffer after any modifications
        " Only if the llmchat buffer is currently active
        normal! G
        redraw

        " Using temp file to avoid command line length limits.
        let l:current_temp_context_file = tempname()
        call writefile(l:lines_to_send, l:current_temp_context_file)
        let l:llm_cmd = 'cat ' . l:current_temp_context_file . ' | ' . g:llm_command
        if !empty(g:llm_model)
            let l:llm_cmd .= ' -m ' . g:llm_model
        endif
        if g:llm_enable_usage
            let l:llm_cmd .= ' -u'
        endif
        if !empty(g:llm_model_temperature)
            let l:llm_cmd .= ' -o temperature ' . g:llm_model_temperature
        endif
        "let l:llm_cmd = 'echo this is a fixed response.'
        "let l:llm_cmd = 'while true; do sleep 5; echo sleeping; done'
        let l:cmd = ['/bin/sh', '-c', l:llm_cmd]

        " Store all job-related info in a single global dictionary
        let l:job_id = job_start(l:cmd, {
            \ 'out_cb': function('s:LLMStreamCallback', [l:llmchat_buffer_nr]),
            \ 'err_cb': function('s:LLMErrorCallback', [l:llmchat_buffer_nr]),
            \ 'exit_cb': function('s:LLMExitCallback', [l:llmchat_buffer_nr, l:current_temp_context_file]),
            \ })

        " Start a polling timer for the job
        let l:timer_id = timer_start(1000, function('s:LLMTimeoutCallback', [l:job_id, l:llmchat_buffer_nr]), {'repeat': -1})

        let g:llm_job_info = {
            \ 'id': l:job_id,
            \ 'buffer_nr': l:llmchat_buffer_nr,
            \ 'temp_file': l:current_temp_context_file,
            \ 'timer_id': l:timer_id,
            \ 'invoke_count': 0,
            \ 'last_output_time': reltime(),
            \ 'spinner_index': 0,
            \ 'spinner_active': v:false
            \ }
    endif
endfunction

function! s:LLMChatOpenWin() abort
    let l:chat_buffer_name = 'llmchat'
    let l:chat_bufnr = bufnr(l:chat_buffer_name)
    let l:is_buffer_visible = v:false

    " Check if the buffer is currently visible in any window
    if l:chat_bufnr != -1
        let l:win_ids = win_findbuf(l:chat_bufnr)
        if !empty(l:win_ids)
            let l:is_buffer_visible = v:true
            call win_gotoid(l:win_ids[0])
            return
        endif
    endif

    " If we reach here, the buffer is either non-existent or exists but is
    " not visible. We need to open it, potentially in a new split.

    if g:llm_chat_new_behavior ==? 'vertical'
        rightbelow vnew
    elseif g:llm_chat_new_behavior ==? 'horizontal'
        rightbelow new
    endif

    if l:chat_bufnr != -1
        " Buffer exists but was not visible, open it
        execute 'buffer ' . l:chat_bufnr
    else
        " Buffer did not exist, create and configure it
        execute 'file ' . l:chat_buffer_name
        setlocal buftype=nofile
        setlocal noswapfile
        setlocal filetype=markdown
        setlocal bufhidden=hide
	" Helps readability without changing buffer contents
	setlocal wrap
	setlocal linebreak
    endif
endfunction

" If last prompt is an empty Prompt, delete it.
function! s:DeleteEmptyPrompt(buffer_nr) abort
    let l:lines = getbufline(a:buffer_nr, 1, '$')
    let l:all_whitespace = v:true

    " Iterate backwards to find the last prompt header
    let l:i = len(l:lines) - 1
    while l:i >= 0
        let matches = matchlist(l:lines[l:i], '\v# \<\<\< (Assistant Response)|^# \>\>\> (User Prompt|Pasted Prompt)|(\S)')
        if !empty(matches)
            " If the first part (starting with '# >>>') matched
            if !empty(matches[1]) || !empty(matches[2])
                break
            " Else, if the second part (any non-whitespace character) matched
            " This implies the first part did not match for the current line
            elseif !empty(matches[3])
                let l:all_whitespace = v:false
            endif
        endif
        let l:i -= 1
    endwhile

    if l:all_whitespace
        call deletebufline(a:buffer_nr, l:i+1, '$')
        " Check if the last line is empty after deletion and delete it if so
        " This check needs to be done on the specific buffer
        if len(getbufline(a:buffer_nr, 1, '$')) > 0 && getbufline(a:buffer_nr, '$')[0] ==? ''
            call deletebufline(a:buffer_nr, '$')
        endif
    endif
endfunction

" Helper function to find the last prompt header and its line number
function! s:GetLastPromptHeader(buffer_nr) abort
    let l:lines = getbufline(a:buffer_nr, 1, '$')
    let l:last_header_type = ''
    let l:last_header_line_nr = -1

    " Iterate backwards to find the last prompt header
    let l:i = len(l:lines) - 1

    while l:i >= 0
        let matches = matchlist(l:lines[l:i], '\v# \<\<\< (Assistant Response)|^# \>\>\> (User Prompt|Pasted Prompt)')
        if !empty(matches)
            if !empty(matches[1])
                let l:last_header_type = matches[1]
            elseif !empty(matches[2])
                let l:last_header_type = matches[2]
            endif
            let l:last_header_line_nr = l:i + 1
            break
        endif
        let l:i -= 1
    endwhile

    return {'type': l:last_header_type, 'line_nr': l:last_header_line_nr}
endfunction

function! s:LLMStreamCallback(buffer_nr, channel, message) abort
    let l:is_at_bottom = (line('.') == line('$'))

    " If spinner is active, remove it before appending new text
    if exists('g:llm_job_info') && g:llm_job_info.spinner_active
        " Check if the last line is the spinner
        let l:last_line = getbufline(a:buffer_nr, '$')[0]
        if !empty(l:last_line) && index(g:llm_spinner_chars, l:last_line) != -1
            call deletebufline(a:buffer_nr, '$')
        endif
        let g:llm_job_info.spinner_active = v:false
    endif

    " Append to the specific buffer
    call appendbufline(a:buffer_nr, '$', split(a:message, '\n'))

    " Update last output time
    if exists('g:llm_job_info')
        let g:llm_job_info.last_output_time = reltime()
    endif

    " If the llmchat buffer is currently active in the current window,
    " and the cursor was at the end, move it to the new end.
    if bufnr('%') == a:buffer_nr && l:is_at_bottom
	normal! G
	redraw
    endif
endfunction

function! s:LLMErrorCallback(buffer_nr, channel, message) abort
    if a:message =~# '^Token usage:'
        " Strip off some unwanted text at end
        echom substitute(a:message, 'output.*', 'output', '')
    else
        echom 'Error from job: ' . a:message
    endif
endfunction

function! llm#LLMIsRunning() abort
    return exists('g:llm_job_info') && job_status(g:llm_job_info.id) ==? 'run'
endfunction

function! llm#LLMCancel() abort
    if llm#LLMIsRunning()
        echom 'Cancelling llm job...'
        call job_stop(g:llm_job_info.id)
        " LLMExitCallback will be triggered by job_stop and handle cleanup
    else
        echom 'No llm job is currently running.'
    endif
endfunction

function! s:LLMTimeoutCallback(job_id, buffer_nr, timer_id) abort
    " Check if the job associated with this timer is still the active job.
    if exists('g:llm_job_info') && g:llm_job_info.id == a:job_id
        let g:llm_job_info.invoke_count += 1

        " Check for new text timeout for spinner
        let l:current_time = reltime()
        let l:time_since_last_output = reltimefloat(reltime(g:llm_job_info.last_output_time))

        if l:time_since_last_output >= 1.0 && job_status(a:job_id) ==? 'run'
	    let l:is_at_bottom = (line('.') == line('$'))

            " Time to show/update spinner
            let g:llm_job_info.spinner_index = (g:llm_job_info.spinner_index + 1) % len(g:llm_spinner_chars)
            let l:spinner_char = g:llm_spinner_chars[g:llm_job_info.spinner_index]

            " If spinner is already active, replace the last line
            if g:llm_job_info.spinner_active
                " Check if the last line is indeed a spinner character
                let l:last_line_content = getbufline(a:buffer_nr, '$')[0]
                if !empty(l:last_line_content) && index(g:llm_spinner_chars, l:last_line_content) != -1
                    call setbufline(a:buffer_nr, '$', l:spinner_char)
                else
                    " Something else was appended, so append the spinner
                    call appendbufline(a:buffer_nr, '$', l:spinner_char)
                endif
            else
                " Spinner not active, append it
                call appendbufline(a:buffer_nr, '$', l:spinner_char)
                let g:llm_job_info.spinner_active = v:true
            endif

            " In case we appended, move cursor to end if in llmchat buffer
	    " and it was already at end.
            if bufnr('%') == a:buffer_nr && l:is_at_bottom
                normal! G
            endif
        endif

        " Existing timeout logic
        if g:llm_job_info.invoke_count >= g:llm_timeout_seconds
            echom 'LLM job timed out after ' . g:llm_timeout_seconds . ' seconds. Cancelling...'
            call llm#LLMCancel()
        endif
    endif
endfunction

function! s:LLMExitCallback(buffer_nr, temp_file, job_id, status) abort
    let l:is_at_bottom = (line('.') == line('$'))

    " Remove spinner if it was active
    if exists('g:llm_job_info') && g:llm_job_info.spinner_active
        " Check if the last line is the spinner
        let l:last_line = getbufline(a:buffer_nr, '$')[0]
        if !empty(l:last_line) && index(g:llm_spinner_chars, l:last_line) != -1
            call deletebufline(a:buffer_nr, '$')
        endif
    endif

    " Clean up the temporary context file associated with this specific job
    if filereadable(a:temp_file)
        call delete(a:temp_file)
    endif

    " Clean up the job info ONLY if it is for the currently tracked job
    if exists('g:llm_job_info') && g:llm_job_info.id == a:job_id
        " Stop the associated timer before unsetting g:llm_job_info
        if exists('g:llm_job_info.timer_id')
            call timer_stop(g:llm_job_info.timer_id)
        endif
        unlet! g:llm_job_info
    endif

    " The Assistant Response will be empty if command failed
    " immediately. If the response is empty for other reasons, may
    " as well clean it up as well.
    call s:DeleteEmptyPrompt(a:buffer_nr)

    " Either last command failed and we deleted response header then
    " leave last User Prompt at end of buffer. Otherwise, add a new
    " User Prompt
    let l:last_header = s:GetLastPromptHeader(a:buffer_nr)
    if l:last_header.type !=? 'User Prompt'
        call appendbufline(a:buffer_nr, '$', ['', '# >>> User Prompt', ''])
        " Only move cursor if the llmchat buffer is currently active and
	" were previously at end of buffer.
        if bufnr('%') == a:buffer_nr && l:is_at_bottom
            normal! G
        endif
    else
    endif
endfunction

function! llm#LLMRead(prompt) abort
    let l:command = g:llm_command
    if !empty(g:llm_model)
        let l:command .= ' -m ' . g:llm_model
    endif
    if !empty(g:llm_model_temperature)
        let l:command .= ' -o temperature ' . g:llm_model_temperature
    endif
    let l:command .= ' ' . shellescape(a:prompt)

    let l:output = system(l:command)
    if v:shell_error
        echom 'llm command failed.'
	return ''
    else
	return trim(l:output)
    endif
endfunction

function! llm#LLMFilter(prompt) abort range
    let l:command = g:llm_command
    if !empty(g:llm_model)
        let l:command .= ' -m ' . g:llm_model
    endif
    if !empty(g:llm_model_temperature)
        let l:command .= ' -o temperature ' . g:llm_model_temperature
    endif
    let l:command .= ' ' . shellescape(a:prompt)

    " llm returns an unwanted line always. Deal with BSD vs Linux tool
    " limitations.
    if has('macunix')
        let l:command .= ' | sed "$d"'
    else
        let l:command .= ' | head -n -1'
    endif
    let l:filter_command = printf('%d,%d!%s', a:firstline, a:lastline, l:command)
    execute l:filter_command
    if v:shell_error
        undo
        echom 'llm command failed.'
    endif
endfunction

function! llm#LLMFix() abort range
    let l:prompt = 'You will be provided text from a vim editing session that reports the file type as "' . &filetype . '".'
    let l:prompt .= '
\ Fix the syntax of this code. Respond with the code including any fixes.
\ Do not alter the functional aspect of the code, but simply fix it and
\ respond with all of it. Do not respond in a markdown code block.'
    call llm#LLMFilter(l:prompt)
endfunction

function! llm#LLMComplete() abort range
    let l:prompt = 'You will be provided text from a vim editing session that reports the file type as "' . &filetype . '".'
    let l:prompt .= '
\ Finish this input. Respond with the text including the completion text.
\ For example: If the user sent "The sky is", you would reply
\ "The sky is blue.". If the input is code, write quality code that is
\ syntactically correct. If the input is text, respond as a wise, succinct
\ writer.'
    call llm#LLMFilter(l:prompt)
endfunction
