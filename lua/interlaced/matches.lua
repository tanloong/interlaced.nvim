#!/usr/bin/env lua

local hl = vim.api.nvim_set_hl
local vim_fn = vim.fn
local vim_api = vim.api

local _H = {}
local M = {
  _H = _H,
  ---@type boolean
  is_hl_matches = true,
  ---@type { id: integer, group: string, pattern: string, priority: integer}[]
  _matches = {},
  ---@type string?
  last_color = nil,
  colors = require("interlaced.colors"),
  group_prefix = "ItColor",
  -- ns = vim.api.nvim_create_namespace("interlaced.nvim"),
  ns = 0,
  cmd = {},
}

-- define colors
for i, v in ipairs(M.colors) do
  hl(M.ns, M.group_prefix .. i, v)
end

_H.randcolor = function()
  return M.group_prefix .. (math.fmod(vim_fn.rand(), #M.colors) + 1)
end

---@param color string|nil
---@param patterns table
_H.matchadd = function(color, patterns)
  if color == "." then
    color = M.last_color or _H.randcolor()
    -- color is cmd-line args
    -- if the caller accepts cmd-line args, a.args will be "" when not provided by user
    -- if the caller is not defined to accept cmd-line args, a.args will be nil
    --   cannot use `not color` because lua consider only nil and false as false,
    --   "" and 0 would be true
  elseif color == "_" or color == nil or color:len() == 0 then
    color = _H.randcolor()
    -- else use {color} as is
  end

  -- directly call matchdelete() and matchadd()
  for _, pattern in ipairs(patterns) do
    -- delete the previously defined match that has the same pattern.
    -- iterating in reverse order to avoid affecting the indices of the
    --   elements that have not yet been checked when an even element is removed
    for i, m in vim.iter(M._matches):rev():enumerate() do
      if m.pattern == pattern then
        -- 1. delete from matches
        vim_fn.matchdelete(m.id)
        -- 2. delete from {M._matches}
        table.remove(M._matches, i)
      end
    end

    _H.set_enable_matches(true)
    -- 1. add to matches
    local id = vim_fn.matchadd(color, pattern)

    -- 2. add to {M._matches}
    -- {M._matches} might be used for setmatches(), which complains about
    --   missing required keys, so should include all 4 of them.
    table.insert(M._matches, { group = color, pattern = pattern, priority = 10, id = id })
    M.last_color = color
  end
end

---@param enable boolean
_H.set_enable_matches = function(enable)
  if enable then
    vim_fn.setmatches(M._matches)
    M.is_hl_matches = true
  else
    M._matches = vim_fn.getmatches()
    M.cmd.ClearMatches()
    M.is_hl_matches = false
  end
end

_H.escape_text = function(s)
  -- Reference: https://github.com/inkarkat/vim-mark/blob/fa0898fe5fa8e13aee991534d6cb44f421f07c2c/autoload/mark.vim#L57
  return vim_fn.substitute(vim_fn.escape(s, [[\^$.*[~]]), [[\n]], [[\\n]], "g")
end


M.cmd.ToggleMatches = function()
  _H.set_enable_matches(not M.is_hl_matches)
end

M.cmd.ClearMatches = function()
  -- there is still a copy of matches in {M._matches}, which will be used for :ItToggleMatches
  vim_fn.clearmatches()
end

M.cmd.ListHighlights = function()
  vim.cmd([[filter /\v^]] .. M.group_prefix .. "/ highlight")
end

M.cmd.ListMatches = function()
  local scrwin = vim_api.nvim_get_current_win()
  vim.cmd.split()
  local bufnr = vim_api.nvim_create_buf(true, true)
  vim_api.nvim_buf_set_name(bufnr, "interlaced://" .. tostring(bufnr))
  vim_api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].buftype = 'nowrite'

  local deleted_matches = {}
  local sort_methods = {
    -- color order
    function(a, b) return a.group < b.group end,
    -- pattern order
    function(a, b) return a.pattern < b.pattern end,
    -- id order
    function(a, b) return a.id < b.id end,
  }
  local sort = 0
  local function cycle_sort()
    -- cycle to the next sort method, thus sort + 1
    sort = (sort % #sort_methods) + 1
    -- lua table is 1-based, thus +1
    table.sort(M._matches, sort_methods[sort])
    local display_lines = {}
    local display_patterns = {}
    local num_length = tostring(#M._matches):len()
    local group_length = vim_fn.max(vim.tbl_map(function(t) return t.group:len() end, M._matches))
    for i, m in ipairs(M._matches) do
      if not vim.list_contains(display_patterns, m.pattern) then
        table.insert(display_lines,
          string.format(
            "%" .. num_length .. "d. " ..
            "%-" .. group_length .. "s " ..
            "%s",
            i,
            m.group,
            m.pattern))
        table.insert(display_patterns, m.pattern)
        vim_fn.matchadd(m.group, _H.escape_text(m.pattern))
      end
    end

    -- allow edit temporarily
    vim.bo[bufnr].modifiable = true
    vim_api.nvim_buf_set_lines(bufnr, 0, -1, true, display_lines)
    vim.bo[bufnr].modifiable = false
  end
  cycle_sort()

  local function delete_match(lineno)
    lineno = lineno or vim_fn.line(".")
    local line = vim_fn.getline(lineno)
    local pattern = vim_fn.substitute(line, [[\v^\d+\.\s*\S+\s*]], "", "")
    -- invalid lines (those with pattern not in matches) will be skipped in this for loop and won't be appended to deleted_matches
    for i, m in vim.iter(M._matches):rev():enumerate() do
      if m.pattern == pattern then
        -- 1. delete from matches
        pcall(vim_fn.matchdelete, m.id, scrwin)
        -- display and display_lineno is used in restore_match()
        m.display = line
        m.display_lineno = lineno
        table.insert(deleted_matches, m)
        -- 2. delete from {M._matches}
        table.remove(M._matches, i)
      end
    end
    -- allow edit temporarily
    vim.bo[bufnr].modifiable = true
    -- delete cursorline, be it valid or not
    vim_fn.deletebufline(bufnr, lineno, lineno)
    vim.bo[bufnr].modifiable = false
  end

  local function restore_match()
    local m = table.remove(deleted_matches)
    if m == nil then return end
    vim_fn.matchadd(m.group, m.pattern, m.priority, m.id, { window = scrwin })
    -- update {matches}
    table.insert(M._matches, m)

    -- allow edit temporarily
    vim.bo[bufnr].modifiable = true
    vim_fn.append(m.display_lineno - 1, m.display)
    vim.bo[bufnr].modifiable = false

    vim_fn.setcursorcharpos(m.display_lineno, 1)
  end

  for _, entry in ipairs({
    { "n", "d", delete_match,  "Delete match(es) of the pattern on cursor line" },
    { "n", "u", restore_match, "Restore the last deleted match" },
    { "n", "q", vim.cmd.quit,  "Quit" },
    { "n", "s", cycle_sort,    "cycle through sort methods (1. pattern, 2. color, 3. insertion order)" },
  }) do
    local modes, from, to, desc = unpack(entry)
    vim.keymap.set(modes, from, to, { desc = desc, silent = true, buffer = true, nowait = true, noremap = true })
  end
end

M.cmd.MatchAddVisual = function(a)
  if #a.fargs > 1 then
    M.error("At most 1 argument is expected but got " .. #a.fargs)
    return
  end

  local pattern = { table.concat(vim_fn.getregion(vim_fn.getpos("'<"), vim_fn.getpos("'>"), { type = "v" }), [[\n]]) }

  local color = a.args
  _H.matchadd(color, pattern)
end

M.cmd.MatchAdd = function(a)
  ---If one pattern is added more than one, the old ones will be discarded. (see highlights module highlight function)
  local patterns = nil
  local color = nil

  -- handle range
  -- :i,jItMatchAdd
  -- :.ItMatchAdd
  if a.range > 0 then
    -- getline() returns a list if {end} is provided
    ---@type table
    patterns = vim.tbl_map(_H.escape_text, vim_fn.getline(a.line1, a.line2))
  end

  -- handle color and pattern(s)
  if #a.fargs > 1 then
    -- :ItMatchAdd {group} {pattern}
    -- :ItMatchAdd {group} {pattern1} {pattern2} ...
    color = table.remove(a.fargs, 1)
    if patterns == nil then
      patterns = a.fargs
    else
      -- :{range}ItMatchAdd group pattern
      -- :{range}ItMatchAdd group pattern1 pattern2 ...
      for pat in a.fargs do
        patterns:insert(pat)
      end
    end
  else
    -- :ItMatchAdd {group} (a.fargs == 1)
    -- :ItMatchAdd (a.fargs == 1)
    -- :{range}ItMatchAdd (a.fargs == 1)
    color = a.args
  end

  -- :ItMatchAdd [group]
  if patterns == nil then
    -- with {list} set as true, expand() will return list instead of string
    ---@type table
    patterns = vim_fn.expand("<cword>", false, true)
    -- search matches that forms whole words
    for i, v in ipairs(patterns) do
      patterns[i] = [[\<]] .. v .. [[\>]]
    end
  end

  -- patterns is list for all above occasions
  _H.matchadd(color, patterns)
end

return M
