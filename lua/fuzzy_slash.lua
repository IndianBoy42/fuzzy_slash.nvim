local M = {
  opts = {
    hl_group = "Search",
    cursor_hl = "CurSearch",
    word_pattern = "[%w%-_]+",
    jump_to_matched_char = true,
    highlight_matched_chars = true,
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
    -- Target generator: fn(args, opts) -> list of {text, row, col, endcol}
    -- Text doesn't actually have to be text in buffer, simply what you want to run the fuzzy matching on
    -- (actually jump_to_matched_char and highlight_matched_char wont work then)
    -- You can add any other data it will be passed through, just dont use (score, index, positions)
    generator = nil,
    -- Match sorter: fn(a, b, opts) -> a < b
    -- Matches are targets augmented with fzf data: {text, row, col, endcol, score=score, index=index, positions=positions}
    -- score and positions are from fuzzy_nvim (fzf, fzy), index is the index in the original target list
    sorter = nil,
    -- Execute the jump to the match: fn(match, opts)
    -- Customize where inside the match you jump to
    jump_to_match = nil,
    -- Do the highlighting: fn(match, ns, hl, opts)
    -- MUST use ns for any extmarks
    highlight_match = nil,
  },
}
local meta_M = { __index = require "fuzzy_slash.utils" }
M = setmetatable(M, meta_M)

local hlsearch_ns = vim.api.nvim_create_namespace "fuzzy_search_hlsearch"

local feedkeys = vim.api.nvim_feedkeys
local termcodes = vim.api.nvim_replace_termcodes
local function t(k) return termcodes(k, true, true, true) end

local get_match_idx = function(matches, cursor, backward)
  local cursorline = cursor[1] - 1
  local idx = 1
  local s, e, j = 1, #matches, 1
  if backward then
    -- TODO:
  end
  for i = s, e, j do
    local match = matches[i]
    local word, line, col = unpack(match)
    if (line - 1) > cursorline or ((line - 1) == cursorline and col > cursor[2]) then
      idx = i
      break
    end
  end
  return idx
end
local get_matches = function(args, fs_opts)
  local winnr = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(winnr)

  local words = fs_opts.generator(args, fs_opts)

  local pat = args.args
  local matches = {}
  local filtered = require("fuzzy_nvim"):filter(pat, words, fs_opts.case_mode)
  for _, result in ipairs(filtered) do
    local word, positions, score, index = unpack(result)
    -- local min, max = minmax(positions)
    word.positions = positions
    word.score = score
    word.index = index
    table.insert(matches, word)
  end
  table.sort(matches, function(a, b) return fs_opts.sorter(a, b, fs_opts) end)

  local idx = get_match_idx(matches, cursor)

  return matches, idx
end

local matches = {}
local match_index = 0

local function highlight_matches(ns, fs_opts)
  for i, match in ipairs(matches) do
    local cursor =
      fs_opts.highlight_match(match, ns, i == match_index and fs_opts.cursor_hl or fs_opts.hl_group, fs_opts)
    if i == match_index then fs_opts.jump_to_match(match, fs_opts) end
  end
end

local function incr_match_index(i)
  match_index = match_index + (i > 0 and 1 or -1)
  if match_index > #matches then match_index = 1 end
  if match_index < 1 then match_index = #matches end
end

local function convert_to_regex()
  local set = {}
  for _, match in ipairs(matches) do
    local word = match[1]
    set[word] = true
  end
  local words = vim.tbl_keys(set)
  local pat = table.concat(words, "\\|")
  -- if not dont_search then
  vim.fn.setreg("/", pat)
  -- FIXME: i have no idea
  feedkeys(t "//<cr>", "m", false)
  -- mappings.register_nN_repeat()
  -- end
  -- return pat
end

local on_key_ns
local last_args
local last_last_args
local last_match_index
local fuzzy_preview = function(fs_opts)
  return function(args, ns, buf)
    if not vim.opt_local.incsearch:get() then return end
    args.args = args.args:gsub(t("[" .. fs_opts.cmdline_next .. fs_opts.cmdline_prev .. "]"), "")

    if args.args ~= last_args then
      vim.cmd.nohlsearch()
      matches, match_index = get_matches(args, fs_opts)

      on_key_ns = vim.on_key(function(k)
        if vim.api.nvim_get_mode().mode ~= "c" then
        end
        -- This is so hacky...
        if k == t "<C-g>" then
          incr_match_index(1)
          feedkeys(t "<bs>", "m", false)
        elseif k == t "<C-t>" then
          incr_match_index(-1)
          feedkeys(t "<bs>", "m", false)
        else
        end
      end, on_key_ns)
      local augrp = vim.api.nvim_create_augroup("fuzzy_search_cmdline_mappings", {})
      vim.api.nvim_create_autocmd("CmdlineLeave", {
        group = augrp,
        pattern = "*",
        once = true,
        callback = function()
          last_last_args = last_args
          last_args = ""
          vim.on_key(nil, on_key_ns)
          on_key_ns = nil
          -- TODO: more robust cleanup
        end,
      })
    end
    last_args = args.args

    highlight_matches(ns, fs_opts)
    -- TODO: render in split buf

    return 1
  end
end

local last_finisher
local fuzzy_finish = function(fs_opts)
  local finisher
  finisher = function(args)
    if (not matches or #matches == 0 or args.args ~= last_last_args) and args.args and #args.args > 0 then
      matches, match_index = get_matches(args, fs_opts)
    end
    if #matches == 0 then
      vim.notify("no matches", vim.log.levels.WARN)
      return
    end
    if match_index == 0 then match_index = get_match_idx(matches, vim.api.nvim_win_get_cursor(0)) end

    local match = matches[match_index]
    fs_opts.jump_to_match(match, fs_opts)

    -- TODO: hlsearch
    if vim.opt_local.hlsearch:get() then
      vim.api.nvim_buf_clear_namespace(0, hlsearch_ns, 0, -1)
      highlight_matches(hlsearch_ns, fs_opts)
    end
    last_match_index = match_index
    match_index = 0

    -- TODO: repeatable, or just loclist
    fs_opts.register_nN_repeat { vim.cmd.FzNext, vim.cmd.FzPrev }
    last_finisher = finisher
  end
  return finisher
end

M.make_command = function(fs_opts)
  fs_opts = fs_opts and setmetatable(fs_opts, { __index = M.opts }) or M.opts
  return fuzzy_finish(fs_opts), {
    nargs = "*",
    preview = fuzzy_preview(fs_opts),
    range = "%",
  }
end

M.opts.generator = M.get_all_words_or_lines
M.opts.jump_to_match = M.jump_to_match
M.opts.sorter = function(a, b) return a.index < b.index end
M.opts.highlight_match = M.highlight_match

M.setup = function(opts)
  if opts then M.opts = setmetatable(opts, { __index = M.opts }) end

  vim.api.nvim_create_user_command(M.opts.Fz, M.make_command())
  vim.api.nvim_create_autocmd("OptionSet", {
    pattern = "hlsearch",
    callback = function() vim.api.nvim_buf_clear_namespace(0, hlsearch_ns, 0, -1) end,
  })
  -- Repeat
  -- TODO: preview the location and allow c-g, c-t
  -- TODO: this is not exactly the same as /? nN
  vim.api.nvim_create_user_command(M.opts.FzNext, function(args)
    match_index = last_match_index
    incr_match_index(1)
    last_finisher(args)
  end, {})
  vim.api.nvim_create_user_command(M.opts.FzPrev, function(args)
    match_index = last_match_index
    incr_match_index(-1)
    last_finisher(args)
  end, {})

  vim.api.nvim_create_user_command(M.opts.FzPattern, convert_to_regex, {})

  -- Clear highlights
  vim.api.nvim_create_user_command(
    M.opts.FzClear,
    function(args) vim.api.nvim_buf_clear_namespace(0, hlsearch_ns, 0, -1) end,
    {}
  )
end

return M
