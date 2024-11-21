#!/usr/bin/env lua

local hl = vim.api.nvim_set_hl
local vim_fn = vim.fn
local vim_api = vim.api

local _H = {}
local M = {
  _H = _H,
  _is_matches_on = true,
  _matches = {},
  colors = require("interlaced.colors"),
  group_prefix = "ItColor",
  ns = vim.api.nvim_create_namespace("interlaced.nvim"),
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
_H.highlight = function(color, patterns)
  if color == "." then
    color = M._matches[#M._matches].group
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
        -- delete from matches
        vim_fn.matchdelete(m.id)
        -- delete from {M._matches}
        table.remove(M._matches, i)
      end
    end

    -- add to matches
    if M._is_matches_on then
      vim_fn.matchadd(color, pattern)
    end

    -- add to {M._matches}
    -- {M._matches} might be used for setmatches(), which complains about
    --   missing required keys, so should include all 4 of them.
    -- The {priority} argument is 10 by default. If the {id} argument is not
    --   specified or -1, matchadd() automatically chooses a free ID.
    table.insert(M._matches, { group = color, pattern = pattern, priority = 10, id = -1 })
  end
end

M.cmd.ToggleMatches = function()
  if M._is_matches_on then
    M._matches = vim_fn.getmatches()
    M.cmd.ClearMatches()
    M._is_matches_on = false
  else
    vim_fn.setmatches(M._matches)
    M._is_matches_on = true
  end
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

  local matches = vim_fn.getmatches(scrwin)
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
    table.sort(matches, sort_methods[sort])
    local display_lines = {}
    local display_patterns = {}
    local num_length = tostring(#matches):len()
    local group_length = vim_fn.max(vim.tbl_map(function(t) return t.group:len() end, matches))
    for i, m in ipairs(matches) do
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
        vim_fn.matchadd(m.group, [[\V]] .. vim_fn.escape(m.pattern, [[\]]))
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
    local new_matches = {}
    for _, match in ipairs(matches) do
      if match.pattern == pattern then
        pcall(vim_fn.matchdelete, match.id, scrwin)
        -- display and display_lineno is used in restore_match()
        match.display = line
        match.display_lineno = lineno
        table.insert(deleted_matches, match)
      else
        table.insert(new_matches, match)
      end
    end
    -- update {matches}
    matches = new_matches

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
    table.insert(matches, m)

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

  local patterns = vim_fn.getregion(vim_fn.getpos("'<"), vim_fn.getpos("'>"), { type = "v" })
  for i, v in ipairs(patterns) do
    patterns[i] = [[\V]] .. v
  end

  local color = a.args
  _H.highlight(color, patterns)
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
    patterns = vim_fn.getline(a.line1, a.line2)
    for i, v in ipairs(patterns) do
      patterns[i] = [[\V]] .. v
    end
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
  _H.highlight(color, patterns)
end

--:ItMatchDelete print matches and ask user to choose one
--:ItMatchDelete . deletes the most recently added match
M.cmd.MatchDelete = function(a)
  a.args = vim.trim(a.args)
  local matches = vim_fn.getmatches()

  if #a.fargs == 0 then
    local choices = { "Select match: " }
    local defined_patterns = {}
    local i = 1
    for _, match in ipairs(matches) do
      if not vim.list_contains(defined_patterns, match.pattern) then
        table.insert(choices, i .. ". " .. match.pattern)
        i = i + 1
      end
    end
    local n = vim_fn.inputlist(choices)
    if not (n >= 1 and n <= i) then
      return
    end
    pattern = vim_fn.substitute(choices[n + 1], [[^]] .. n .. [[\. ]], "", "")
    for _, match in ipairs(matches) do
      if match.pattern == pattern then
        vim_fn.matchdelete(match.id)
      end
    end
  elseif a.args == "." then
    -- use the id of the most recently added match
    if #matches == 0 then
      M.error("No matches to delete")
      return
    end

    pcall(vim_fn.matchdelete, matches[#matches].id)
    return
  else
    M.error("Invalid arguments")
    return
  end
end

return M
