if exists("g:loaded_fuzzy") || &cp || !has('nvim')
  finish
endif
let g:loaded_fuzzy = 1

if !exists("g:fuzzy_bufferpos")
  let g:fuzzy_bufferpos = 'below'
endif

if !exists("g:fuzzy_opencmd")
  let g:fuzzy_opencmd = 'edit'
endif

if !exists("g:fuzzy_executable")
  let g:fuzzy_executable = 'fzy'
endif

if !exists("g:fuzzy_rg")
  let g:fuzzy_rg = 'rg'
endif

if !exists("g:fuzzy_winheight")
  let g:fuzzy_winheight = 12
endif

if !exists("g:fuzzy_rootcmds")
  let g:fuzzy_rootcmds = [
    \ 'git rev-parse --show-toplevel',
    \ 'hg root'
  \ ]
endif

let s:fuzzy_job_id = 0
let s:fuzzy_prev_window = -1
let s:fuzzy_prev_window_height = -1
let s:fuzzy_bufnr = -1

if !executable(g:fuzzy_executable)
  echoerr "Fuzzy: '" . g:fuzzy_executable . "' was not found in your path"
endif

if !executable(g:fuzzy_rg)
  echoerr "Fuzzy: '" . g:fuzzy_rg . "' was not found in your path"
endif

function! s:strip(str)
  return substitute(a:str, '\n*$', '', 'g')
endfunction

function! s:fuzzy_getroot()
  for cmd in g:fuzzy_rootcmds
    let result = system(cmd)
    if v:shell_error == 0
      return s:strip(result)
    endif
  endfor
  return "."
endfunction

function! s:fuzzy_find_file(root)
  return systemlist(g:fuzzy_rg . " --hidden -g '!.git' -g '!package-lock.json' -g '!yarn.lock' --files -F " . a:root . ' 2>/dev/null')
endfunction

function! s:fuzzy_find_content(query)
  let query = empty(a:query) ? '.' : shellescape(a:query)
  return systemlist(g:fuzzy_rg . " -n -S --no-heading --hidden -g '!.git' -g '!package-lock.json' -g '!yarn.lock' " . query . " . 2>/dev/null")
endfunction

command! -nargs=? FuzzyGrep call s:fuzzy_grep(<q-args>)
command! -nargs=? FuzzyOpen call s:fuzzy_open(<q-args>)
command! FuzzyKill call s:fuzzy_kill()

autocmd FileType fuzzy tnoremap <buffer> <Esc> <C-\><C-n>:FuzzyKill<CR>

function! s:fuzzy_kill()
  echo
  call jobstop(s:fuzzy_job_id)
endfunction

function! s:fuzzy_grep(str) abort
  try
    let contents = s:fuzzy_find_content(a:str)
  catch
    echoerr v:exception
    return
  endtry

  let opts = {'lines': g:fuzzy_winheight, 'statusfmt': 'FuzzyGrep %s (%d results)', 'root': '.'}

  function! opts.handler(result) abort
    let parts = split(join(a:result), ':')
    let name = parts[0]
    let lnum = parts[1]
    let text = parts[2]

    return {'name': name, 'lnum': lnum}
  endfunction

  return s:fuzzy(contents, opts)
endfunction

function! s:fuzzy_open(root) abort
  let root = empty(a:root) ? s:fuzzy_getroot() : a:root
  exe 'lcd' root

  try
    let files = s:fuzzy_find_file('.')
  catch
    echoerr v:exception
    return
  finally
    lcd -
  endtry

  let opts = {'lines': g:fuzzy_winheight, 'statusfmt': 'FuzzyOpen %s (%d files)', 'root': root}
  function! opts.handler(result)
    return {'name': join(a:result)}
  endfunction

  return s:fuzzy(files, opts)
endfunction

function! s:fuzzy(choices, opts) abort
  let inputs = tempname()
  let outputs = tempname()

  if !executable(g:fuzzy_executable)
    echoerr "Fuzzy: the executable '" . g:fuzzy_executable . "' was not found in your path"
    return
  endif

  " Clear the command line.
  echo

  call writefile(a:choices, inputs)

  let command = g:fuzzy_executable . " -l " . a:opts.lines . " > " . outputs . " < " . inputs
  let opts = {'outputs': outputs, 'handler': a:opts.handler, 'root': a:opts.root}

  function! opts.on_exit(id, code, _event) abort
    " NOTE: The order of these operations is important: Doing the delete first
    " would leave an empty buffer in netrw. Doing the resize first would break
    " the height of other splits below it.
    call win_gotoid(s:fuzzy_prev_window)
    exe 'silent' 'bdelete!' s:fuzzy_bufnr
    exe 'resize' s:fuzzy_prev_window_height

    if a:code != 0 || !filereadable(self.outputs)
      return
    endif

    let results = readfile(self.outputs)
    if !empty(results)
      for result in results
        let file = self.handler([result])
        exe 'lcd' self.root
        silent execute g:fuzzy_opencmd fnameescape(expand(file.name))
        lcd -
        if has_key(file, 'lnum')
          silent execute file.lnum
          normal! zz
        endif
      endfor
    endif
  endfunction

  let s:fuzzy_prev_window = win_getid()
  let s:fuzzy_prev_window_height = winheight('%')

  if bufnr(s:fuzzy_bufnr) > 0
    exe 'keepalt' g:fuzzy_bufferpos a:opts.lines . 'sp' bufname(s:fuzzy_bufnr)
  else
    exe 'keepalt' g:fuzzy_bufferpos a:opts.lines . 'new'
    let s:fuzzy_job_id = termopen(command, opts)
    let b:fuzzy_status = printf(
      \ a:opts.statusfmt,
      \ fnamemodify(opts.root, ':~:.'),
      \ len(a:choices))
    setlocal statusline=%{b:fuzzy_status}
    set norelativenumber
    set nonumber
  endif
  let s:fuzzy_bufnr = bufnr('%')
  set filetype=fuzzy
  startinsert
endfunction
