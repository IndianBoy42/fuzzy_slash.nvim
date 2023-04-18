local M = {}
local meta_M = {}

-- Not the gfind we deserve, but the one we need
function M.find_all_matches(line, pat, init, plain)
  local col = 0
  return function()
    local start, fin = line:find(pat, init, plain)
    if start then
      local w, s, e = line:sub(start, fin), col + start - 1, col + fin
      line = line:sub(fin + 1)
      col = col + fin
      return w, s, e
    else
      return nil
    end
  end
end

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

function M.jump_to_match(match, opts)
  local word, line, col, endcol = unpack(match)
  local cursor
  if opts.jump_to_matched_char == true then
    local start, fin = minmax(match.positions)
    cursor = { line, col + start - 1 }
  else
    cursor = { line, col }
  end
  vim.api.nvim_win_set_cursor(0, cursor)
end

function M.highlight_match(match, ns, hl, opts)
  local word, line, col, endcol = unpack(match)
  if ns then
    if opts.highlight_matched_chars then
      local start, fin = minmax(match.positions)
      vim.api.nvim_buf_set_extmark(0, ns, line - 1, col + start - 1, { end_col = col + fin, hl_group = hl })
    else
      vim.api.nvim_buf_set_extmark(0, ns, line - 1, col, { end_col = endcol, hl_group = hl })
    end
  end
end

function M.sort_by_index(a, b) return a.index < b.index end
function M.sort_by_score(a, b) return a.score > b.score end
function M.sort_by_key(k)
  return function(a, b) return a[k] < b[k] end
end
function M.sort_by_chain(ks)
  return function(a, b)
    for _, k in ipairs(ks) do
      local t = a[k] - b[k]
      if t < 0 then
        return true
      elseif t > 0 then
        return false
      end
    end
    return false
  end
end

M.filtered_words = function(filter)
  return function(lines, words, row_start, opts, args)
    row_start = row_start or 0
    local i = #words
    for row, line in ipairs(lines) do
      for w, s, e in M.find_all_matches(line, opts.word_pattern) do
        local word = { w, row + row_start, s, e }
        if not filter or filter(word) then
          i = i + 1
          words[i] = word
        end
      end
    end
    return words
  end
end
M.get_words = M.filtered_words(nil)
M.by_scanning_lines = function(get)
  return function(args, opts)
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
    words = get(vim.api.nvim_buf_get_lines(bufnr, cursorline, e, false), words, cursorline, opts, args)
    words = get(vim.api.nvim_buf_get_lines(bufnr, s, cursorline, false), words, s, opts, args)
    return words
  end
end
M.get_lines = function(lines, words, row_start)
  local j = #words
  for i, line in ipairs(lines) do
    words[i + j] = { line, i + row_start, 1, #line }
  end
  return words
end
M.get_all_words = M.by_scanning_lines(M.get_words)
M.get_all_lines = M.by_scanning_lines(M.get_lines)
M.get_all_words_or_lines = function(args, opts)
  local scan
  if args.args:match("^" .. opts.word_pattern .. "$") then
    scan = M.get_all_words
  else
    scan = M.get_all_lines
  end
  return scan(args, opts)
end
M.from_first_char = M.by_scanning_lines(function(lines, words, row_start, opts, args)
  local first_char = args.args and #args.args > 0 and args.args:sub(1, 1)
  if not first_char then return words end
  local i = #words
  for row, line in ipairs(lines) do
    local end_ = #line
    for w, s, e in M.find_all_matches(line, "[" .. first_char .. first_char:upper() .. "]", 1, false) do
      words[i] = { line:sub(s + 1), row + row_start, s, end_ }
      i = i + 1
    end
  end
  return words
end)

local gnt = vim.treesitter.get_node_text
local gnr = vim.treesitter.get_node_range
local ins_node_text = function(node, words, j, bufnr, args)
  local sr, sc, er, ec = gnr(node)
  if sr ~= er then
    er = sr
    ec = #vim.api.nvim_buf_get_lines(bufnr, sr, er + 1, false)[1]
  end
  -- if sr >= args.line1 and er <= args.line2 then
  if (sr >= args.line1 and sr <= args.line2) or (er <= args.line2 and er >= args.line1) then
    words[j] = { gnt(node, bufnr, {}), sr + 1, sc, ec - 1 }
    j = j + 1
  end
  return j
end

M.get_ts_locals = function(args, opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local ts_locals = require "nvim-treesitter.locals"
  local local_nodes = ts_locals.get_locals(bufnr)
  local words = {}
  local j = 1
  for i, local_node in ipairs(local_nodes) do
    local node = (local_node.definition and local_node.definition.node)
      or (local_node.reference and local_node.reference.node)
    if node then j = ins_node_text(node, words, j, bufnr, args) end
  end
  return words
end

local recurse_nodes = require("nvim-treesitter.locals").recurse_local_nodes
M.get_ts_textobjects = function(args, opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local queries = require "nvim-treesitter.query"
  local objs
  if args.args:sub(1, 1) ~= "@" then
    objs = queries.get_matches(bufnr, "textobjects")
  else
    objs = queries.get_capture_matches(0, args.fargs[1], "textobjects")
    args.args = table.concat(args.fargs, " ", 2)
  end
  local targets = {}
  local j = 1
  for _, obj in ipairs(objs) do
    recurse_nodes(obj, function(_, node, name, _) j = ins_node_text(node, targets, j, bufnr, args) end)
  end
  M.debug_last_words = targets
  return targets
end

M.get_lsp_symbol = function(args, opts)
  local symbols = {}
  return symbols
end

M.get_diagnostic = function(args, opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local diags = vim.diagnostic.get(bufnr, opts.diagnostic_opts or {})
  local words = {}
  for i, diag in ipairs(diags) do
    local line = diag.lnum
    local start = diag.col
    local finish = diag.end_col
    words[i] = { diag.message, line + 1, start, start + 1 }
  end
  return words
end

return setmetatable(M, meta_M)
