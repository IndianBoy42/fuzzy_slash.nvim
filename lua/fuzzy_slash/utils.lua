local M = {}
local meta_M = {}

local function minmax(list)
  if #list == 0 then error "Zero length table to minmax" end

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

function M.highlight_match(match, ns, hl, fs_opts)
  local word, line, col, endcol = unpack(match)
  if ns then
    if fs_opts.highlight_matched_chars then
      local start, fin = minmax(match.positions)
      vim.api.nvim_buf_set_extmark(0, ns, line - 1, col + start - 1, { end_col = col + fin, hl_group = hl })
    else
      vim.api.nvim_buf_set_extmark(0, ns, line - 1, col, { end_col = endcol, hl_group = hl })
    end
  end
end

M.filtered_words = function(filter)
  return function(lines, words, row_start, fs_opts, args)
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
  return function(args, fs_opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local winnr = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(winnr)
    local cursorline = cursor[1] - 1

    local s, e = 0, -1
    if args.range == 2 then
      s = args.line1
      e = args.line2
    end

    local words = {}
    words = get(vim.api.nvim_buf_get_lines(bufnr, cursorline, e, false), words, cursorline, fs_opts, args)
    words = get(vim.api.nvim_buf_get_lines(bufnr, s, cursorline, false), words, s, fs_opts, args)
    utils.tmp = words
    return words
  end
end
M.get_all_words = M.by_scanning_lines(M.get_words)
M.get_all_words_or_lines = function(args, fs_opts)
  local scan
  if args.args:match("^" .. fs_opts.word_pattern .. "$") then
    scan = M.by_scanning_lines(M.get_words)
  else
    scan = M.by_scanning_lines(function(lines, words, row_start)
      local j = #words
      for i, line in ipairs(lines) do
        words[i + j] = { line, i + row_start, 1, #line }
      end
      return words
    end)
  end
  return scan(args, fs_opts)
end

M.get_ts_locals = function(args, fs_opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local locals = require "nvim-treesitter.locals"
  local local_nodes = locals.get_locals(bufnr)
  local words = {}
  local gnt = vim.treesitter.get_node_text
  local gnr = vim.treesitter.get_node_range
  local j = 1
  for i, local_node in ipairs(local_nodes) do
    local n = (local_node.definition and local_node.definition.node)
      or (local_node.reference and local_node.reference.node)
    if n then
      local sr, sc, er, ec = gnr(n)
      if sr ~= er then
        er = sr
        ec = #vim.api.nvim_buf_get_lines(bufnr, sr, er, false)[1]
      end
      if sr >= args.line1 and er <= args.line2 then
        words[j] = { gnt(n, bufnr, {}), sr, sc, ec }
        j = j + 1
      end
    end
  end
  return words
end

M.get_ts_query_matches = function(args, fs_opts)
  if args.args:sub(1, 1) ~= "@" then
  else
  end
  return
end

return setmetatable(M, meta_M)
