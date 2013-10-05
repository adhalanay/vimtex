" {{{1 latex#init
let s:initialized = 0
function! latex#init()
  call s:init_environment()
  call s:init_errorformat()

  call latex#toc#init(s:initialized)
  call latex#fold#init(s:initialized)
  call latex#motion#init(s:initialized)
  call latex#change#init(s:initialized)
  call latex#latexmk#init(s:initialized)
  call latex#complete#init(s:initialized)

  "
  " This variable is used to allow a distinction between global and buffer
  " initialization
  "
  let s:initialized = 1
endfunction

" {{{1 latex#info
function! latex#info()
  echo "Buffer data"
  echo printf('           id: %-s', b:latex.id)
  echo printf('fold sections: %-s', string(b:latex.fold_sections))
  echo "\n"

  echo "Latex blobs"
  let n = -1
  for data in g:latex#data
    let n += 1
    if n > 0
      echo "\n"
    endif
    let d = copy(data)
    let d.aux = d.aux()
    let d.out = d.out()
    let d.log = d.log()
    echo printf('%6s: %-s', 'id', n)
    for [key, val] in sort(items(d), "s:info_sort_func")
      if key =~ '\vaux|out|root|log|tex'
        let val = s:truncate(val)
      endif
      echo printf('%6s: %-s', key, val)
    endfor
  endfor
endfunction

" {{{1 latex#help
function! latex#help()
  if g:latex_default_mappings
    echo "Latex mappings"
    nmap <buffer>
    vmap <buffer>
    omap <buffer>
  endif
endfunction

" {{{1 latex#reinit
function! latex#reinit()
  "
  " Stop latexmk processes (if running)
  "
  call latex#latexmk#stop_all()

  "
  " Reset variables
  "
  let s:initialized = 0
  unlet g:latex#data
  bufdo unlet b:notbslash
  bufdo unlet b:notcomment
  bufdo unlet b:latex

  "
  " Reinitialize
  "
  bufdo call latex#init()
endfunction

" {{{1 latex#view
function! latex#view()
  let outfile = g:latex#data[b:latex.id].out()
  if !filereadable(outfile)
    echomsg "Can't view: Output file is not readable!"
    return
  endif

  silent execute '!' . g:latex_viewer . ' ' . outfile . ' &>/dev/null &'
  if !has("gui_running")
    redraw!
  endif
endfunction
" }}}1

" {{{1 s:init_environment
function! s:init_environment()
  "
  " Initialize global and local data blobs
  "
  call latex#util#set_default('g:latex#data', [])
  call latex#util#set_default('b:latex', {})

  "
  " Initialize some common patterns
  "
  call latex#util#set_default('b:notbslash', '\%(\\\@<!\%(\\\\\)*\)\@<=')
  call latex#util#set_default('b:notcomment',
        \ '\%(\%(\\\@<!\%(\\\\\)*\)\@<=%.*\)\@<!')

  "
  " Create new or link to old blob
  "
  let main = s:get_main_tex()
  let id   = s:get_id(main)
  if id >= 0
    let b:latex.id = id
  else
    let data = {}
    let data.tex  = main
    let data.root = fnamemodify(data.tex, ':h')
    let data.base = fnamemodify(data.tex, ':t')
    let data.name = fnamemodify(data.tex, ':t:r')
    function data.aux() dict
      return s:get_main_ext(self, 'aux')
    endfunction
    function data.log() dict
      return s:get_main_ext(self, 'log')
    endfunction
    function data.out() dict
      return s:get_main_ext(self, g:latex_latexmk_output)
    endfunction

    call add(g:latex#data, data)
    let b:latex.id = len(g:latex#data) - 1
  endif

  if g:latex_default_mappings
    nnoremap <silent><buffer> <localleader>li :call latex#info()<cr>
    nnoremap <silent><buffer> <localleader>lh :call latex#help()<cr>
    nnoremap <silent><buffer> <localleader>lv :call latex#view()<cr>
    nnoremap <silent><buffer> <LocalLeader>lR :call latex#reinit()<cr>
  endif
endfunction

" {{{1 s:init_errorformat
function! s:init_errorformat()
  "
  " Note: The error formats assume we're using the -file-line-error with
  "       [pdf]latex. For more info, see |errorformat-LaTeX|.
  "

  " Push file to file stack
  setlocal efm+=%+P**%f

  " Match errors
  setlocal efm=%E!\ LaTeX\ %trror:\ %m
  setlocal efm+=%E%f:%l:\ %m
  setlocal efm+=%E!\ %m

  " More info for undefined control sequences
  setlocal efm+=%Z<argument>\ %m

  " Show warnings
  if g:latex_errorformat_show_warnings
    " Ignore some warnings
    for w in g:latex_errorformat_ignore_warnings
      let warning = escape(substitute(w, '[\,]', '%\\\\&', 'g'), ' ')
      exe 'setlocal efm+=%-G%.%#'. warning .'%.%#'
    endfor
    setlocal efm+=%+WLaTeX\ %.%#Warning:\ %.%#line\ %l%.%#
    setlocal efm+=%+W%.%#\ at\ lines\ %l--%*\\d
    setlocal efm+=%+WLaTeX\ %.%#Warning:\ %m
    setlocal efm+=%+W%.%#%.%#Warning:\ %m
  endif

  " Ignore unmatched lines
  setlocal efm+=%-G%.%#
endfunction
" }}}1

" {{{1 s:get_id
function! s:get_id(main)
  if exists('g:latex#data') && !empty(g:latex#data)
    let id = 0
    while id < len(g:latex#data)
      if g:latex#data[id].tex == a:main
        return id
      endif
      let id += 1
    endwhile
  endif

  return -1
endfunction

" {{{1 s:get_main_tex
function! s:get_main_tex()
  if !search('\C\\begin\_\s*{document}', 'nw')
    let tex_files  = glob('*.tex', 0, 1) + glob('../*.tex', 0, 1)
    call filter(tex_files,
          \ "count(g:latex_main_tex_candidates, fnamemodify(v:val,':t:r'))")
    if !empty(tex_files)
      return fnamemodify(tex_files[0], ':p')
    endif
  endif

  return expand('%:p')
endfunction

" {{{1 s:get_main_ext
function! s:get_main_ext(texdata, ext)
  " Create set of candidates
  let candidates = [
        \ a:texdata.name,
        \ g:latex_build_dir . '/' . a:texdata.name,
        \ ]

  " Search through the candidates
  for f in map(candidates,
        \ 'a:texdata.root . ''/'' . v:val . ''.'' . a:ext')
    if filereadable(f)
      return fnamemodify(f, ':p')
    endif
  endfor

  " Return empty string if no entry is found
  return ''
endfunction

" {{{1 s:info_sort_func
function! s:info_sort_func(a, b)
  if a:a[1][0] == "!"
    " Put cmd's way behind
    return 1
  elseif a:b[1][0] == "!"
    " Put cmd's way behind
    return -1
  elseif a:a[1][0] == "/" && a:b[1][0] != "/"
    " Put full paths behind
    return 1
  elseif a:a[1][0] != "/" && a:b[1][0] == "/"
    " Put full paths behind
    return -1
  elseif a:a[1][0] == "/" && a:b[1][0] == "/"
    " Put full paths behind
    return -1
  else
    return a:a[1] > a:b[1] ? 1 : -1
  endif
endfunction

" {{{1 s:truncate
function! s:truncate(string)
  if len(a:string) >= winwidth('.') - 9
    return a:string[0:10] . "..." . a:string[-winwidth('.')+23:]
  else
    return a:string
  endif
endfunction
" }}}1

" vim:fdm=marker:ff=unix