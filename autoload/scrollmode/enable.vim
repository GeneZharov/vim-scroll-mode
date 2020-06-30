function s:cmd(str) abort
  return (has("nvim") ? "<Cmd>" : ":<C-u>") . a:str
endfunction

let s:default_step = 5

" Can't map <Esc> to "exit" because it conflicts with mappings like <Up> or
" <Down> in Vim (though in Neovim works).
let s:default_actions = {
  \ "up": ["k", "<Up>"],
  \ "down": ["j", "<Down>"],
  \ "pagedown": ["l"],
  \ "pageup": ["h"],
  \ "bottom": ["b"],
  \ "top": ["<Space>"],
  \ "exit": [";"],
  \ "bdelete": ["-"]
  \ }

function! s:echo_mode() abort
  echo "-- SCROLL --"
endfunction

function! s:highlight() abort
  if line("w0") == 1 || line("w$") == line("$")
    highlight! link StatusLine DiffChange
  else
    highlight! link StatusLine DiffAdd
  endif
  redraw!
endfunction

function! s:on_motion() abort
  call s:highlight()
  call s:echo_mode()
endfunction

function! <SID>gen_motion(rhs) abort
  let w:scroll_mode_cursor_pos = v:null
  return a:rhs
endfunction

function! s:map(keys, rhs) abort
  for lhs in a:keys
    exe "nnoremap <silent> <buffer>" lhs a:rhs
  endfor
endfunction

function! s:map_motion(keys, rhs) abort
  for lhs in a:keys
    exe printf(
      \ "nnoremap <silent> <buffer> <expr> %s <SID>gen_motion(\"%s\")",
      \ lhs,
      \ escape(a:rhs, '"')
      \ )
  endfor
endfunction

function! s:valid_map(map) abort
  return
    \ type(a:map) == v:t_dict &&
    \ scrollmode#util#all(
    \   values(a:map),
    \   {_, x -> type(x) == v:t_list}
    \ ) &&
    \ scrollmode#util#all(
    \   scrollmode#util#unnest(values(a:map)),
    \   {_, x -> type(x) == v:t_string}
    \ )
endfunction

function! s:valid_conf() abort
  if (
    \ exists("g:scroll_mode_actions") &&
    \ !s:valid_map(g:scroll_mode_actions)
    \ )
    echoerr "g:scroll_mode_actions has wrong type"
    return v:false
  endif
  if (
    \ exists("g:scroll_mode_mappings") &&
    \ !s:valid_map(g:scroll_mode_mappings)
    \ )
    echoerr "g:scroll_mode_mappings has wrong type"
    return v:false
  endif
  if (
    \ exists("g:scroll_mode_step") &&
    \ type(g:scroll_mode_step) != v:t_number
    \ )
    echoerr "g:scroll_mode_step must be a number"
    return v:false
  endif
  return v:true
endfunction

function! s:affected_keys(dicts) abort
  let mappings = scrollmode#util#reduce(
    \ a:dicts,
    \ {acc, _, dict -> acc + values(dict)},
    \ []
    \ )
  return uniq(sort(scrollmode#util#unnest(mappings)))
endfunction

function! scrollmode#enable#enable() abort
  if (!s:valid_conf())
    return
  endif

  if (line("$") == 1)
    " No scrolling for new buffers because WinLeave is not triggered for them
    echo "ScrollMode: Nothing to scroll"
    return
  endif

  let filename = expand("%:p")
  let step = exists("g:scroll_mode_step") ? g:scroll_mode_step : s:default_step
  let actions = extend(
    \ copy(s:default_actions),
    \ exists("g:scroll_mode_actions") ? g:scroll_mode_actions : {}
    \ )
  let mappings = exists("g:scroll_mode_mappings")
    \ ? g:scroll_mode_mappings
    \ : {}

  " Window variables
  let w:scroll_mode_cursor_pos = getpos(".")
  let w:scroll_mode_enabled = v:true
  let w:scroll_mode_scrolloff = &scrolloff
  let w:scroll_mode_cuc = &cuc
  let w:scroll_mode_mapped_keys = s:affected_keys([actions, mappings])
  let w:scroll_mode_dumped_keys = scrollmode#util#dump_mappings(
    \ w:scroll_mode_mapped_keys,
    \ "n",
    \ v:false
    \ )

  normal! M

  echohl ModeMsg
  call s:highlight()
  call s:echo_mode()

  " Options
  set scrolloff=999
  setlocal nocuc

  " Mappings
  call s:map_motion(actions.down, step . "gjg^")
  call s:map_motion(actions.up, step . "gkg^")
  call s:map_motion(actions.pagedown, "<C-f>M")
  call s:map_motion(actions.pageup, "<C-b>M")
  call s:map_motion(actions.bottom, "GM")
  call s:map_motion(actions.top, "ggM")
  call s:map(actions.exit, s:cmd("call scrollmode#disable#disable()<CR>"))
  call s:map(actions.bdelete, s:cmd("call scrollmode#disable#disable() \\| bd<CR>"))

  for mapping in items(mappings)
    call s:map(mapping[1], mapping[0])
  endfor

  augroup scroll_mode
    au CursorMoved * call s:on_motion()
    au InsertEnter * call scrollmode#disable#disable()
    exe printf(
      \ "au WinLeave,BufWinLeave %s call scrollmode#disable#disable()",
      \ escape(scrollmode#util#to_unix_path(filename), "^$.~*[ ")
      \ )
  augroup END
endfunction
