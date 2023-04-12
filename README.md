# Fuzzy Slash

Use fuzzy search in the current buffer in the same way as you would `/?`, no need for telescope or some gui. Uses the commnd-preview feature.

[Screencast from 04-12-2023 10:26:32 PM.webm](https://user-images.githubusercontent.com/5981889/231489301-29419b0e-ed3e-4f98-a8e0-a6ee02f314e9.webm)

Install it (lazy.nvim):

```lua
{
    "IndianBoy42/fuzzy_slash.nvim",
    dependencies = { "tzachar/fuzzy.nvim", }
    -- Configure and lazy load as you want
}
```

Try it:

```vim
:Fz <search> " Updates live (if inccommand is set)
:FzNext
:FzPrev
```

Bind it:

```lua
vim.keymap.set("n", ":Fz ") -- Don't use <cmd> you need to type here
```

Not much configuration for not much functionality. Only need to pass the keys you want to change.

```lua
{
    hl_group = "Search",
    cursor_hl = "CurSearch",
    word_pattern = "[%w%-_]+",
    register_nN_repeat = function(nN)
        -- called after a fuzzy search with a tuple of functions that are effectively `n, N`
        local n, N = unpack(nN)
        -- Dynamically map this to n, N
        -- Left as an exercise to the reader
    end,
    -- Wanna rename the commands for some reason?, change the rhs
    Fz = "Fz",
    FzNext = "FzNext",
    FzPrev = "FzPrev",
    FzPattern = "FzPattern",
    FzClear = "FzClear", -- Similar to :nohlsearch
    -- See :h incsearch, move between matches without leaving the cmdline
    cmdline_next = "<c-g>",
    cmdline_prev = "<c-t>",
    cmdline_addchar = "<c-t>",
}
```

## TODOs

- [x] Do the search
- [ ] Multi window?
- [ ] Notify when there is only one word matched
- [ ] Quickfix/loclist integration
