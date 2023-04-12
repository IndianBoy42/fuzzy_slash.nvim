# Fuzzy Slash

Use fuzzy search in the current buffer in the same way as you would `/?`, no need for telescope or some gui. Uses the commnd-preview feature.

[Screencast from 04-12-2023 10:26:32 PM.webm](https://user-images.githubusercontent.com/5981889/231489301-29419b0e-ed3e-4f98-a8e0-a6ee02f314e9.webm)

Install it (lazy.nvim):

```lua
{
  "IndianBoy42/fuzzy_slash.nvim",
  dependencies = {
    { "tzachar/fuzzy.nvim", dependencies = { { "nvim-telescope/telescope-fzf-native.nvim", build = "make" } } },
  },
  -- Configure and lazy load as you want
}
```

See [fuzzy.nvim](https://github.com/tzachar/fuzzy.nvim)'s README.md to make sure you get fzf/fzy installed correctly

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
    jump_to_matched_char = true,
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
    -- Target generator: fn() -> list of {text, row, col, endcol}
    -- Text doesn't actually have to be text in buffer, simply what you want to run the fuzzy matching on
    -- You can add any other data it will be passed through, just dont use (score, index, positions)
    generator = nil,
    -- Match sorter: fn(a, b) -> a < b
    -- Matches are targets augmented with fzf data: {text, row, col, endcol, score=score, index=index, positions=positions}
    -- score and positions are from fuzzy_nvim (fzf, fzy), index is the index in the original target list
    sorter = nil,
    -- Execute the jump to the match: fn(match)
    -- Customize where inside the match you jump to
    jump_to_match = nil,
    -- Do the highlighting: fn(match, ns, hl)
    -- MUST use ns for any extmarks
    highlight_match = nil,
}
```

# API

PRELIMINARY: Make your own commands with custom target generators and sorters, please tell me what interesting things you make, or what you want to make

```lua
-- Any options/keys in the opts table here will override the defaults for this custom command
-- Thus you can customize any aspect of the behaviour, especially target generation
vim.api.nvim_create_user_command("MyFz", M.make_command(opts))
```

## TODOs

- [x] Do the search
- [ ] Multi window?
- [ ] Notify when there is only one word matched
- [ ] Quickfix/loclist integration
- [ ] Bugginess in next/prev? (maybe customizable sorting)
- [ ] Treesitter and LSP?
  - [ ] Modularize the code for different target generators
