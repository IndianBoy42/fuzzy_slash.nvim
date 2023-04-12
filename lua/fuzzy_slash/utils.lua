local M = {}
local meta_M = {}

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

function M.jump_to_match(match, fs_opts)
	local word, line, col, endcol = unpack(match)
	local cursor
	if fs_opts.jump_to_matched_char == true then
		local start, fin = minmax(match.positions)
		cursor = { line, col + start - 1 }
	else
		cursor = { line, col }
	end
	vim.api.nvim_win_set_cursor(0, cursor)
end

function M.highlight_match(match, ns, hl)
	local word, line, col, endcol = unpack(match)
	local start, fin = minmax(match.positions)
	if ns then
		vim.api.nvim_buf_set_extmark(0, ns, line - 1, col + start - 1, { end_col = col + fin - 1, hl_group = hl })
	end
end

M.filtered_words = function(filter)
	return function(lines, words, row_start, fs_opts)
		row_start = row_start or 0
		local i = #words
		local col = 0
		for row, line in ipairs(lines) do
			while #line > 0 do
				local start, fin = line:find(fs_opts.word_pattern)
				if start then
					local word = {
						line:sub(start, fin),
						row + row_start,
						col + start - 1,
						col + fin,
					}
					if not filter or filter(word) then
						i = i + 1
						words[i] = word
					end
					col = col + fin
					line = line:sub(fin + 1)
				else
					break
				end
			end
			col = 0
		end
		return words
	end
end
M.get_words = M.filtered_words(nil)
M.by_scanning_lines = function(get)
	return function(fs_opts)
		local bufnr = vim.api.nvim_get_current_buf()
		local winnr = vim.api.nvim_get_current_win()
		local cursor = vim.api.nvim_win_get_cursor(winnr)
		local cursorline = cursor[1] - 1

		local words = {}
		words = get(vim.api.nvim_buf_get_lines(bufnr, cursorline, -1, false), words, cursorline, fs_opts)
		words = get(vim.api.nvim_buf_get_lines(bufnr, 0, cursorline, false), words, 0, fs_opts)
		return words
	end
end
M.get_all_words = M.by_scanning_lines(M.get_words)

return setmetatable(M, meta_M)
