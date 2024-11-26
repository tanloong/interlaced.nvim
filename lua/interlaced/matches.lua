#!/usr/bin/env lua

local hl = vim.api.nvim_set_hl
local vim_fn = vim.fn
local vim_api = vim.api

logger = require("interlaced.logger")

local _H = {}
local M = {
  _H = _H,
  ---@type boolean
  is_hl_matches = true,
  ---@type { id: integer, group: string, pattern: string, priority: integer}[]
  _matches = vim_fn.getmatches(),
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
---@param pattern string
---@param win integer|nil
_H.matchadd = function(color, pattern, win, id)
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
  elseif vim_fn.hlID(color) == 0 then
    logger.error("Highlight group is empty or does not exist")
    return
  end

  _H.matchdelete(pattern, win)

  _H.set_enable_matches(true)
  -- 1. add to matches
  id = id or -1
  if win then
    id = vim_fn.matchadd(color, pattern, 10, id, { window = win })
  else
    id = vim_fn.matchadd(color, pattern, 10, id)
  end

  -- 2. add to {M._matches}
  -- {M._matches} might be used for setmatches(), which complains about
  --   missing required keys, so should include all 4 of them.
  table.insert(M._matches, { group = color, pattern = pattern, priority = 10, id = id })
  M.last_color = color
end

---@param pattern string
---@param win integer|nil
---@return integer|nil integer the id of the last delete match whose pattern equals to the give one
---Unlike the builtin matchdelete(), this func takes a pattern instead of an id
_H.matchdelete = function(pattern, win)
  local id = nil
  if not pattern then return id end

  -- delete the previously defined match that has the same pattern.
  -- iterating in reverse order to avoid affecting the indices of the
  --   elements that have not yet been checked when an even element is removed
  for i, m in vim.iter(M._matches):rev():enumerate() do
    if m.pattern == pattern then
      -- 1. delete from matches
      vim_fn.matchdelete(m.id, win)
      id = m.id
      -- 2. delete from {M._matches}
      table.remove(M._matches, i)
    end
  end
  return id
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

M.cmd.MatchToggle = function()
  _H.set_enable_matches(not M.is_hl_matches)
end

M.cmd.ClearMatches = function()
  -- there is still a copy of matches in {M._matches}, which will be used for :ItToggleMatches
  vim_fn.clearmatches()
end

M.cmd.ListHighlights = function()
  vim.cmd([[filter /\v^]] .. M.group_prefix .. "/ highlight")
end

---@return integer the window id of the ListMatches window
M.cmd.ListMatches = function()
  local origwin = vim_api.nvim_get_current_win()
  vim.cmd([[botright split | resize ]] .. vim.o.cmdwinheight)
  local listwin = vim_api.nvim_get_current_win()
  local bufnr = vim_api.nvim_create_buf(true, true)
  vim_api.nvim_buf_set_name(bufnr, "interlaced://" .. tostring(bufnr))
  vim_api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].buftype = 'nowrite'

  local deleted_matches = {}
  local sort_options = {
    -- id order
    function(a, b) return a.id < b.id end,
    -- color order
    function(a, b) return a.group < b.group end,
    -- pattern order
    function(a, b) return a.pattern < b.pattern end,
  }
  local sort_options_n = #sort_options
  local sort = 0
  local function cycle_sort()
    if next(M._matches) == nil then return end
    -- cycle to the next sort method, thus sort + 1
    sort = (sort % sort_options_n) + 1
    -- lua table is 1-based, thus +1
    table.sort(M._matches, sort_options[sort])
    local display_lines = {}
    local display_patterns = {}
    local num_length = tostring(#M._matches):len()
    local group_length = math.max(unpack(vim.tbl_map(function(t) return t.group:len() end, M._matches)))
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

  ---Refresh the listwin when matches are changed
  local function refresh_match()
    -- when listwin is initially created, sort=0;
    -- after that sort will always be [1, 3], see cycle_sort();
    -- minus 1 makes sort be [0, 2]
    sort = sort - 1
    -- after a minus 1 the same sort will still be used, acting like a refresh
    cycle_sort()
  end

  local function delete_match(lineno)
    lineno = lineno or vim_fn.line(".")
    local line = vim_fn.getline(lineno)
    local pattern = line:match([[^%s*%d+%.%s*%S+%s*(.*)%s*$]])
    -- invalid lines (those with pattern not in matches) will be skipped in this for loop and won't be appended to deleted_matches
    for i, m in vim.iter(M._matches):rev():enumerate() do
      if m.pattern == pattern then
        -- 1. delete from matches
        pcall(vim_fn.matchdelete, m.id, origwin)
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
    vim_api.nvim_buf_set_lines(bufnr, lineno - 1, lineno, true, {}) -- nvim_buf_set_lines is zero-based, end-exclusive
    vim.bo[bufnr].modifiable = false
  end

  local function restore_match()
    local m = table.remove(deleted_matches)
    if m == nil then return end
    vim_fn.matchadd(m.group, m.pattern, m.priority, m.id, { window = origwin })
    -- update {matches}
    table.insert(M._matches, m)

    -- allow edit temporarily
    vim.bo[bufnr].modifiable = true
    vim_fn.append(m.display_lineno - 1, m.display)
    vim.bo[bufnr].modifiable = false

    vim_fn.setcursorcharpos(m.display_lineno, 1)
  end

  local function change_match()
    local line = vim_api.nvim_get_current_line()
    -- {group name} does allow whitespace (:h group-name), use \S is OK
    local orig_color = line:match([[^%s*%d+%.%s*(%S+)]])
    local orig_pattern = line:match([[^%s*%d+%.%s*%S+%s*(.*)%s*$]])

    new_color = vim_fn.input({
      default = orig_color,
      prompt = "Highlight group: ",
      completion = "highlight",
      cancelreturn = vim.NIL
    })
    if new_color == vim.NIL then return end
    new_pattern = vim_fn.input({ default = orig_pattern, prompt = "Pattern: ", cancelreturn = vim.NIL })
    if new_pattern == vim.NIL then return end

    local id = _H.matchdelete(orig_pattern, origwin)
    _H.matchadd(new_color, new_pattern, origwin, id)

    refresh_match()
  end

  for _, entry in ipairs({
    { "n", "d", delete_match,  "Delete match(es) of the pattern on cursor line" },
    { "n", "u", restore_match, "Restore the last deleted match" },
    { "n", "q", vim.cmd.quit,  "Quit" },
    { "n", "s", cycle_sort,    "cycle through sort methods (1. pattern, 2. color, 3. insertion order)" },
    { "n", "c", change_match,  "modify the pattern or color of the match under the cursor" },
  }) do
    local modes, from, to, desc = unpack(entry)
    vim.keymap.set(modes, from, to, { desc = desc, silent = true, buffer = true, nowait = true, noremap = true })
  end

  vim_fn.win_execute(listwin, [[normal! G]])
  return listwin
end

M.cmd.MatchAddVisual = function()
  -- obtain pattern first, got error if after the listwin is created, don't know why...
  -- consider user's selectd text as plain text and escape special chars in the pattern; matchadd() by defualt consider the given pattern magic
  local pattern = table.concat(
    vim.tbl_map(_H.escape_text, vim_fn.getregion(vim_fn.getpos("'<"), vim_fn.getpos("'>"), { type = "v" })), [[\n]])

  local listwin = M.cmd.ListMatches()
  _H.cmap_remote_listwin(true, listwin)
  vim.cmd.redraw() -- let the ListMatches split window display

  ---If one pattern is added more than once, the old ones will be discarded. (see _H.matchadd function)
  local color = vim_fn.input({ prompt = "Highlight group: ", completion = "highlight", cancelreturn = vim.NIL })

  -- should be BEFORE the _H.matchadd to ensure the matchadd is applied to the work window
  vim_api.nvim_win_close(listwin, true)
  vim.cmd.redraw() -- let the ListMatches split window disappear
  _H.cmap_remote_listwin(false, listwin)

  if color == vim.NIL then return end
  -- should be AFTER the listwin is closed to ensure the matchadd is applied to the work window
  _H.matchadd(color, pattern)
end

M.cmd.MatchAdd = function()
  local listwin = M.cmd.ListMatches()
  _H.cmap_remote_listwin(true, listwin)
  vim.cmd.redraw() -- let the ListMatches split window display

  ---If one pattern is added more than once, the old ones will be discarded. (see _H.matchadd function)
  local color = vim_fn.input({ prompt = "Highlight group: ", completion = "highlight", cancelreturn = vim.NIL })

  -- should be BEFORE the _H.matchadd to ensure the matchadd is applied to the work window
  vim_api.nvim_win_close(listwin, true)
  vim.cmd.redraw() -- let the ListMatches split window disappear
  _H.cmap_remote_listwin(false, listwin)

  if color == vim.NIL then return end

  -- consider user's input as a regex pattern and does not escape special chars in the pattern
  local pattern = vim_fn.input({ prompt = "Pattern: ", cancelreturn = vim.NIL })
  if pattern == vim.NIL then return end

  -- should be AFTER the listwin is closed to ensure the matchadd is applied to the work window
  _H.matchadd(color, pattern)
end

---@param enable boolean
---@param listwin integer
_H.cmap_remote_listwin = function(enable, listwin)
  local strokes = { "<c-e>", "<c-y>", "<c-d>", "<c-u>", "<c-f>", "<c-b>" }
  if enable then
    for _, stroke in ipairs(strokes) do
      vim.keymap.set("c", stroke,
        function()
          local code = vim.api.nvim_replace_termcodes(stroke, true, false, true)
          vim_fn.win_execute(listwin, [[normal! ]] .. code)
          vim.cmd.redraw()
        end, { silent = true, buffer = true, nowait = true, noremap = true })
    end
  else
    for _, stroke in ipairs(strokes) do
      -- 会报错不存在对应的map，不知道为什么
      pcall(vim_api.nvim_del_keymap, "c", stroke)
    end
  end
end

return M
