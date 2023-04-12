local M = {
	opts = {
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
	},
}
local meta_M = {}

local feedkeys = vim.api.nvim_feedkeys
local termcodes = vim.api.nvim_replace_termcodes
local function t(k)
	return termcodes(k, true, true, true)
end

local function minmax(list)
	if #list == 0 then
		error("Zero length table to minmax")
	end

	local min = list[1]
	local max = list[1]
	for _, v in ipairs(list) do
		min = math.min(min, v)
		max = math.max(max, v)
	end
	return min, max
end
local get_matches_on = function(pat, lines, row_start, matches)
	matches = matches or {}
	local m = require("fuzzy_nvim")

	local words = {}
	local i = 1
	local col = 0
	for row, line in ipairs(lines) do
		while #line > 0 do
			local start, fin = line:find(M.opts.word_pattern)
			if start then
				words[i] = { line:sub(start, fin), row + row_start, col + start - 1, col + fin }
				col = col + fin
				line = line:sub(fin + 1)
				i = i + 1
			else
				break
			end
		end
		col = 0
	end

	local matches_len = #matches
	local filtered = m:filter(pat, words, M.opts.case_mode)
	for _, result in ipairs(filtered) do
		local word, positions, score, index = unpack(result)
		-- local min, max = minmax(positions)
		word.positions = positions
		word.score = score
		word.index = index + matches_len
		table.insert(matches, word)
	end
	return matches
end
local get_match_idx = function(matches, cursor, backward)
	local cursorline = cursor[1] - 1
	local idx = 1
	local s, e, j = 1, #matches, 1
	if backward then
		s, e, j = #matches, 1, -1
	end
	for i = s, e, j do
		local match = matches[i]
		local word, line, col, endcol = unpack(match)
		if (line - 1) > cursorline or ((line - 1) == cursorline and col > cursor[2]) then
			idx = i
			break
		end
	end
	return idx
end
local get_matches = function(pat)
	local bufnr = vim.api.nvim_get_current_buf()
	local winnr = vim.api.nvim_get_current_win()
	local cursor = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())
	local cursorline = cursor[1] - 1
	local after_lines = vim.api.nvim_buf_get_lines(bufnr, cursorline, -1, false)
	local before_lines = vim.api.nvim_buf_get_lines(bufnr, 0, cursorline, false)

	local matches = get_matches_on(pat, after_lines, cursorline)
	matches = get_matches_on(pat, before_lines, 0, matches)
	table.sort(matches, function(a, b)
		return a.index < b.index
	end)

	local idx = get_match_idx(matches, cursor)

	return matches, idx
end

local matches = {}
local match_index = 0

local function preview_match(match, ns, hl)
	local word, line, col, endcol = unpack(match)
	local start, fin = minmax(match.positions)
	if ns then
		vim.api.nvim_buf_set_extmark(0, ns, line - 1, col + start - 1, { end_col = endcol, hl_group = hl })
	end
	return { line, col + start - 1 }
end
local function preview_matches(ns)
	for i, match in ipairs(matches) do
		local cursor = preview_match(match, ns, i == match_index and M.opts.cursor_hl or M.opts.hl_group)
		if i == match_index then
			vim.api.nvim_win_set_cursor(0, cursor)
		end
	end
end

local function incr_match_index(i)
	match_index = match_index + (i > 0 and 1 or -1)
	if match_index > #matches then
		match_index = 1
	end
	if match_index < 1 then
		match_index = #matches
	end
end

local function convert_to_regex(dont_search)
	local set = {}
	for _, match in ipairs(matches) do
		local word, line, col, endcol = unpack(match)
		set[word] = true
	end
	local words = vim.tbl_keys(set)
	local pat = table.concat(words, "\\|")
	-- if not dont_search then
	vim.fn.setreg("/", pat)
	-- FIXME: i have no idea
	feedkeys(t("//<cr>"), "m", false)
	mappings.register_nN_repeat()
	-- end
	-- return pat
end

local on_key_ns
local last_args
local last_last_args
local last_match_index
local fuzzy_preview = function(args, ns, buf)
	if not vim.opt_local.incsearch:get() then
		return
	end
	args.args = args.args:gsub(t("[" .. M.opts.cmdline_next .. M.opts.cmdline_prev .. "]"), "")

	if args.args ~= last_args then
		vim.cmd.nohlsearch()
		matches, match_index = get_matches(args.args)

		on_key_ns = vim.on_key(function(k)
			if vim.api.nvim_get_mode().mode ~= "c" then
			end
			-- This is so hacky...
			if k == t("<C-g>") then
				incr_match_index(1)
				feedkeys(t("<bs>"), "m", false)
			elseif k == t("<C-t>") then
				incr_match_index(-1)
				feedkeys(t("<bs>"), "m", false)
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
				-- vim.keymap.del("c", "<C-g>", {})
				-- vim.keymap.del("c", "<C-t>", {})
				-- TODO: more robust cleanup
			end,
		})
	end
	last_args = args.args

	preview_matches(ns)
	-- TODO: render in split buf

	return 1
end

local hlsearch_ns = vim.api.nvim_create_namespace("fuzzy_search_hlsearch")

local fuzzy_finish = function(args, bwd)
	if (not matches or #matches == 0) and args.args and #args.args > 0 then
		matches, match_index = get_matches(args.args)
	end
	if args.args and #args.args > 0 and args.args ~= last_last_args then
		matches, match_index = get_matches(args.args)
	end
	if #matches == 0 then
		vim.notify("no matches", vim.log.levels.WARN)
		return
	end
	if match_index == 0 then
		match_index = get_match_idx(matches, vim.api.nvim_win_get_cursor(0), bwd)
	end

	local match = matches[match_index]
	local word, line, col, endcol = unpack(match)
	local start, fin = minmax(match.positions)
	local cursor = { line, col + start - 1 }
	vim.api.nvim_win_set_cursor(0, cursor)

	-- TODO: hlsearch
	if vim.opt_local.hlsearch:get() then
		vim.api.nvim_buf_clear_namespace(0, hlsearch_ns, 0, -1)
		preview_matches(hlsearch_ns)
	end
	last_match_index = match_index
	match_index = 0

	-- TODO: repeatable, or just loclist
	M.opts.register_nN_repeat({ vim.cmd.FzNext, vim.cmd.FzPrev })
end

M.setup = function(opts)
	M.opts = setmetatable(opts, { __index = M.opts })

	vim.api.nvim_create_user_command(M.opts.Fz, fuzzy_finish, {
		nargs = "*",
		preview = fuzzy_preview,
	})
	vim.api.nvim_create_autocmd("OptionSet", {
		pattern = "hlsearch",
		callback = function()
			vim.api.nvim_buf_clear_namespace(0, hlsearch_ns, 0, -1)
		end,
	})
	-- Repeat
	-- TODO: preview the location and allow c-g, c-t
	vim.api.nvim_create_user_command(M.opts.FzNext, function(args)
		match_index = last_match_index
		incr_match_index(1)
		fuzzy_finish(args)
	end, {})
	vim.api.nvim_create_user_command(M.opts.FzPrev, function(args)
		match_index = last_match_index
		incr_match_index(-1)
		fuzzy_finish(args)
	end, {})

	vim.api.nvim_create_user_command(M.opts.FzPattern, convert_to_regex, {})

	-- Clear highlights
	vim.api.nvim_create_user_command(M.opts.FzClear, function(args)
		vim.api.nvim_buf_clear_namespace(0, hlsearch_ns, 0, -1)
	end, {})
end

return setmetatable(M, meta_M)
