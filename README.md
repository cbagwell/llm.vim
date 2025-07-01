# llm.vim - AI Assistant for Vim

`llm.vim` is a Vim plugin that integrates with
[Simon Willison's llm](https://llm.datasette.io/en/stable/)
command-line tool to provide an AI chat assistant directly within Vim. It
manages a dedicated chat buffer, sends prompts to the `llm` tool, and streams
responses back into the buffer, allowing for an interactive AI experience
without leaving your editor.

## Features

  * **Integrated Chat Buffer:** A dedicated `llmchat` buffer for all your AI
    interactions.
  * **Context Management:** Automatically includes previous chat history in
    prompts.
  * **Flexible Prompting:** Send prompts directly as arguments, type them
    interactively, or include visual selections/entire files as context.
  * **Job Management:** Commands to cancel running AI jobs and check their
    status.
  * **Timeout Functionality:** Configurable timeout for `llm` jobs to prevent
    indefinite waiting.

## Requirements

This plugin requires the external `llm` command-line tool to be installed
and available in your system's PATH. Ensure it is already configured with
your desired LLM provider (e.g., OpenAI, Anthropic, etc.).

## Installation

Install using a plugin manager like `vim-plug`:

  1.  Add the following line to your `~/.vimrc` or `~/.config/nvim/init.vim`:

      ```vim
      Plug 'cbagwell/llm.vim'
      ```

  2.  Run `:PlugInstall` in Vim.

## Keymaps

The following keymaps are active when in the `llmchat` buffer:

*   `<CR>` (Enter): Sends the current prompt in the `llmchat` buffer to the
    `llm` tool, effectively calling `:LLMChat`.
*   `<C-c>` (Ctrl-C): Cancels any currently running `llm` job, equivalent to
    calling `:LLMCancel`.
*   `[[` and `]]`: By default, these jump between markdown headers. In
    `llmchat.md`, this means you can jump between `Prompt` and `Response`
    headers. However, since responses may contain additional markdown headers
    you may wish to update your `~/.vimrc` with more specific mappings to jump
    only between `User Prompt` and `Assistant Response` headers, like this
    example.  Because the response from llm can be hard to read, you
    can use '[[' to quickly jump to last response header and then use
    '=]]' to re-indent and line wrap the response.

    ```vim
    augroup llmchat_install
        autocmd!
        " Jump backward and forward to'# >>>' or '# <<<' marker
        autocmd FileType markdown if expand('%:t') == 'llmchat.md' | nnoremap <silent><buffer> [[ :<C-U>call search('^#\\s\\+\\(>>>\\\\|<<<\).*', "bsW")<CR>| endif
        autocmd FileType markdown if expand('%:t') == 'llmchat.md' | nnoremap <silent><buffer> ]] :<C-U>call search('^#\\s\\+\\(>>>\\\\|<<<\).*', "sW")<CR>| endif
        autocmd FileType markdown if expand('%:t') == 'llmchat.md' | setlocal autoindent | endif
        autocmd FileType markdown if expand('%:t') == 'llmchat.md' | nnoremap = :set operatorfunc=llm#LLMReformatOperator<CR>g@| endif
        autocmd FileType markdown if expand('%:t') == 'llmchat.md' | vnoremap <expr> = llm#LLMReformatOperator(visualmode())| endif
    augroup END
    ```

## Commands

  * **:LLMChat**
    * Opens or switches to the `llmchat` buffer and interacts with the `llm`
    tool.
    * Prompt can be passed in or editted within `llmchat` buffer.
    * Optionally paste in context using visual selection or ranges.
  * **:LLMRead**
    * Uses `llm` to read a prompt and add the response to the next line in
      the current buffer.
      The function llm#LLMRead(prompt) can also be used to return a
      string. While in insert mode, you can use this syntax:
     `<C-r>=llm#LLMRead('Return a dogs name.  Just the name itself.')`
  * **:LLMCancel**
    * Cancels any currently running `llm` job. If no job is running, it will
      display a message.
  * **:LLMIsRunning**
    * Echoes "1" if an `llm` job is currently running, "0" otherwise.
  * **:LLMFix**
    * Sends the current visual selection/range/ling to `llm` to fix any
      syntatical errors and replaces with the results.
  * **:LLMComplete**
    * Sends the current visual selection/range/line to `llm` to complete it.
      Can be used both for implementing a function based on comment
      description or to complete incomplete sentences/paragraphs.
  * **:LLMFilter**
    * Sends the current visual selection/range/line to `llm` to filter or
      transform it. The prompt given to `:LLMFilter` guides the transformation.
      For example: `:'<,'>LLMFilter Improve this text. Return only the
      original text with improvements.`

## Usage

### Start a New Chat or Continue an Existing One

```vim
:LLMChat
```

This will open the `llmchat` buffer. If it's a new chat or the last response
was from `llm`, it will add a new "User Prompt" header. You can then type
your prompt and press `<CR>` (or move off the line) and call `:LLMChat` again
to send it.

### Send a Direct Prompt

```vim
:LLMChat What is the capital of France?
```

This will immediately send "What is the capital of France?" as a "User Prompt"
to `llm`, along with any existing chat history in the `llmchat` buffer.

### Send a Visual Selection as Context

  1.  Select lines in any buffer using visual mode (e.g., `Vj`).
  2.  Call `:LLMChat`:

      ```vim
      :'<,'>LLMChat
      ```

      The selected lines will be added to the `llmchat` buffer as a
      "Pasted Prompt". If you then call `:LLMChat` with an argument, or if
      the last prompt was a user prompt, the pasted content will be part of
      the context sent to `llm`.

### Send an Entire File as Context

```vim
:%LLMChat
```

This will add the entire content of the current file to the `llmchat` buffer
as a "Pasted Prompt".

### Continue a Conversation

Simply type your next prompt under the last "User Prompt" header in the
`llmchat` buffer, then call `:LLMChat` (without arguments). The entire buffer
content will be sent as context. You are also free to modify any older context
to help guide the conversation.

## Configuration

  * `g:llm_timeout_seconds` (Default: `300` seconds / 5 minutes)
     This variable sets the timeout for `llm` jobs in seconds. If the `llm` job
     does not complete within this time, it will be automatically cancelled.
     To change it, add the following to your `~/.vimrc` or
     `~/.config/nvim/init.vim`:

    ```vim
    let g:llm_timeout_seconds = 600 " Set timeout to 10 minutes
    ```

  * `g:llm_command` (Default: `'llm'`)
    This variable defines the command used to invoke the `llm` tool. You can
     set it to a specific path or a custom script if `llm` is not in your PATH
     or if you are using a wrapper.
     To change it, add the following to your `~/.vimrc` or
     `~/.config/nvim/init.vim`:

    ```vim
    let g:llm_command = '/usr/local/bin/llm' " Set to absolute path
    ```

  * `g:llm_enable_usage` (Default: `v:false`)
    This variable controls whether the `-u` option is added to the `llm`
    command, which enables token usage reporting. When enabled, the last line
    of `llm` response will include token usage statistics.
    To disable it, add the following to your `~/.vimrc` or
    `~/.config/nvim/init.vim`:

    ```vim
    let g:llm_enable_usage = v:false
    ```

  * `g:llm_chat_new_behavior` (Default: `'vertical'`)
    This variable controls how the `llmchat` buffer is opened when `:LLMChat`
    is invoked.
    Possible values are:
    * `'vertical'`: (Default) Opens the `llmchat` buffer in a new vertical
       split window to the right of the current window.
    * `'horizontal'`: Opens the `llmchat` buffer in a new horizontal split
      window below the current window.
    * `'current'`: Opens the `llmchat` buffer in the current window.

    To change it, add one of the following to your `~/.vimrc` or
    `~/.config/nvim/init.vim`:

    ```vim
    let g:llm_chat_new_behavior = 'horizontal'
    ```

    **Tip:** You can use `CTRL-W |` to make a vertical split full screen,
    `CTRL-W _` to make a horizontal split full screen, and `CTRL-W =` to
    return all splits to original size.

  * `g:llm_model` (Default: `''`)
    This variable specifies the LLM model to use with the `llm` command's
    `-m` option. If set to an empty string, the `-m` option will not be used,
    allowing `llm` to use its default model.
    To set a specific model, add the following to your `~/.vimrc` or
    `~/.config/nvim/init.vim`:

    ```vim
    let g:llm_model = 'gpt-4o'
    ```

  * `g:llm_model_temperature` (Default: `''`)
    This variable specifies the temperature to use with the `llm` command's
    `-o temperature` option. If set to an empty string, the `-o temperature`
    option will not be used, allowing `llm` to use its default temperature.
    To set a specific temperature, add the following to your `~/.vimrc` or
    `~/.config/nvim/init.vim`:

    ```vim
    let g:llm_model_temperature = '0.4'
    ```

  * `g:llm_spinner_chars` (Default: `['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']`)
    This variable defines the characters used for the loading spinner displayed
    in the `llmchat` buffer while an LLM job is running. You can customize the
    array with any Unicode characters or ASCII characters to change the spinner's
    appearance.
    To change it, add the following to your `~/.vimrc` or
    `~/.config/nvim/init.vim`:

    ```vim
    let g:llm_spinner_chars = ['-', '\\', '|', '/']
    ```

  * `g:llm_popup_notifications` (Default: `v:true`)
    This variable controls whether popup notifications are displayed for `llm`
    status. Set to `v:false` to disable these popups.
    To disable it, add the following to your `~/.vimrc` or
    `~/.config/nvim/init.vim`:

    ```vim
    let g:llm_popup_notifications = v:false
    ```

  * `g:llm_stream_reformat_response` (Default: `v:true`)
    This variable controls whether streamed Assistant responses are
    automatically reformatted using `gqq` as they are appended to the
    `llmchat` buffer. When set to `v:true`, each line is rewrapped and
    indented. When set to `v:false`, no automatic reformatting occurs during
    streaming, and you can manually reformat sections using the
    `llm#LLMReformatOperator` (e.g., `gq` or `=` with appropriate keymaps).
    To disable it, add the following to your `~/.vimrc` or
    `~/.config/nvim/init.vim`:

    ```vim
    let g:llm_stream_reformat_response = v:false
    ```


## Notes

* If an `llm` job is already running when `:LLMChat` is called, the previous
  job will be cancelled before a new one starts.
* Error messages from the `llm` command will be displayed using `echom`.
* Fenced code in `llmchat` can be improved by setting
  `let g:markdown_fenced_languages = ['c', 'bash=sh', 'python]` as well
  as other languages you will work with. Markdown will look better if
  you have `set conceallevel=2.
