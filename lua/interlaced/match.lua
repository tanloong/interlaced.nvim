#!/usr/bin/env lua

local hl = vim.api.nvim_set_hl
local vim_fn = vim.fn
local vim_api = vim.api
local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

logger = require("interlaced.logger")
utils = require("interlaced.utils")

local _H = {}
local M = {
  _H = _H,
  ---@type boolean
  is_hl_matches = true,
  ---@type table<string, { id: integer, group: string, priority: integer}>
  _matches = utils.match_list2dict(vim_fn.getmatches()),
  _deleted_matches = {},
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
---@param winid integer|nil
_H.matchadd = function(color, pattern, winid, matchid)
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

  _H.matchdelete(pattern, winid)

  -- 1. add to matches
  matchid = matchid or -1
  if winid then
    matchid = vim_fn.matchadd(color, pattern, 10, matchid, { window = winid })
  else
    matchid = vim_fn.matchadd(color, pattern, 10, matchid)
  end
  -- 2. add to {M._matches}
  -- {M._matches} might be used for setmatches(), which complains about missing
  -- required keys, so should include all 4 of them.
  M._matches[pattern] = { group = color, priority = 10, id = matchid }
  M.last_color = color

  _H.set_enable_matches(true)
end

---@param pattern string
---@param winid integer|nil
---@return table|nil # the id of the last delete match whose pattern equals to the give one
---Unlike the builtin matchdelete(), this func takes a pattern instead of an id
_H.matchdelete = function(pattern, winid)
  if not pattern then return nil end

  local m = M._matches[pattern]
  if m == nil then return nil end
  local matchid = m.id
  -- 1. delete from matches
  pcall(vim_fn.matchdelete, matchid, winid)
  -- 2. delete from {M._matches}
  M._matches[pattern] = nil

  m.pattern = pattern
  return m
end

---@param enable boolean
_H.set_enable_matches = function(enable)
  if enable then
    if M.is_hl_matches then return end
    vim_fn.setmatches(utils.match_dict2list(M._matches))
    M.is_hl_matches = true
  else
    if not M.is_hl_matches then return end
    M._matches = utils.match_list2dict(vim_fn.getmatches())
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

---@return integer, integer the window id and buffer number
M.cmd.ListMatches = function()
  local origwinid = vim_api.nvim_get_current_win()
  vim.cmd([[botright split | resize ]] .. vim.o.cmdwinheight)
  local listwinid = vim_api.nvim_get_current_win()
  local bufnr = vim_api.nvim_create_buf(true, true)
  vim_api.nvim_buf_set_name(bufnr, "interlaced://" .. tostring(bufnr))
  vim_api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].buftype = 'nowrite'

  autocmd("WinLeave",
    {
      buffer = bufnr,
      group = augroup("interlaced", { clear = true }),
      command = [[quit]]
    })

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
    local matches = utils.match_dict2list(M._matches)
    table.sort(matches, sort_options[sort])
    local display_lines = {}
    local display_patterns = {}
    local id_len = math.max(unpack(vim.tbl_map(function(t) return tostring(t.id):len() end, matches)))
    local grp_len = math.max(unpack(vim.tbl_map(function(t) return t.group:len() end, matches)))
    for _, m in ipairs(matches) do
      if not vim.list_contains(display_patterns, m.pattern) then
        table.insert(display_lines,
          string.format(
            "%" .. id_len .. "d " ..
            "%-" .. grp_len .. "s " ..
            "%s",
            m.id,
            m.group,
            m.pattern))
        table.insert(display_patterns, m.pattern)
        vim_fn.matchadd(m.group, "\\<" .. _H.escape_text(m.group) .. "\\>")
      end
    end

    vim_api.nvim_buf_set_lines(bufnr, 0, -1, true, display_lines)
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
    local pattern = line:match([[^%s*%d+%s*%S+%s*(.*)%s*$]])
    -- invalid lines (those with pattern not in matches) will be skipped in this for loop and won't be appended to deleted_matches
    local m = _H.matchdelete(pattern, origwinid)
    -- display and display_lineno is used in restore_match()
    m.display = line
    m.display_lineno = lineno
    table.insert(M._deleted_matches, m)

    -- delete cursorline, be it valid or not
    vim_api.nvim_buf_set_lines(bufnr, lineno - 1, lineno, true, {}) -- nvim_buf_set_lines is zero-based, end-exclusive
  end

  local function restore_match()
    local m = table.remove(M._deleted_matches)
    if m == nil then return end
    vim_fn.matchadd(m.group, m.pattern, m.priority, m.id, { window = origwinid })
    -- update {matches}
    M._matches[m.pattern] = { group = m.group, id = m.id, priority = m.priority }

    vim_fn.append(m.display_lineno - 1, m.display)

    vim_fn.setcursorcharpos(m.display_lineno, 1)
  end

  local function change_match()
    local line = vim_api.nvim_get_current_line()
    local id = line:match([[^%s*(%S+)]])
    -- {group name} does not allow whitespace (:h group-name), use \S is OK
    local color = line:match([[^%s*%S+%s*(%S+)]])
    local pattern = line:match([[^%s*%S+%s*%S+%s*(.*)%s*$]])

    if id == "_" then
      id = -1
    else
      id = tonumber(id)
      success, msg = pcall(vim_fn.matchdelete, id, origwinid)
      if success then
        for _pat, _id_grp_prio in pairs(M._matches) do
          if _id_grp_prio.id == id then
            M._matches[_pat] = nil
            break
          end
        end
      end
    end
    _H.matchadd(color, pattern, origwinid, id)
    vim_api.nvim_feedkeys(vim_api.nvim_replace_termcodes([[<C-\><C-N><Esc>]], true, false, true), "n", false)

    refresh_match()
  end

  for _, entry in ipairs({
    { "n", "D", delete_match,  "Delete match(es) of the pattern on cursor line" },
    { "n", "U", restore_match, "Restore the last deleted match" },
    { "n", "s", cycle_sort,
      "cycle through sort methods (1. pattern, 2. color, 3. insertion order)" },
    { { "n", "i", "v", "s" }, "<enter>", change_match, "modify the pattern or color of the match under the cursor" },
  }) do
    local modes, from, to, desc = unpack(entry)
    vim.keymap.set(modes, from, to, { desc = desc, silent = true, buffer = true, nowait = true, noremap = true })
  end

  vim_fn.win_execute(listwinid, [[normal! G]])
  return listwinid, bufnr
end

M.cmd.MatchAddVisual = function()
  -- consider user's selectd text as plain text and escape special chars in the pattern; matchadd() by defualt consider the given pattern magic
  local pattern = table.concat(
    vim.tbl_map(_H.escape_text, vim_fn.getregion(vim_fn.getpos("'<"), vim_fn.getpos("'>"), { type = "v" })), [[\\n]])

  local listwin, listbuf = M.cmd.ListMatches()
  local linestart = vim_api.nvim_buf_get_lines(listbuf, 0, 1, true)[1] == "" and 0 or -1
  vim_fn.win_execute(listwin,
    [[call nvim_buf_set_lines(0, ]] ..
    linestart .. [[, -1, 0, ["_ _ ]] .. pattern .. [["]) | exe "normal! G02wv$\<c-g>"]])
end

M.cmd.MatchAdd = function()
  local listwin, listbuf = M.cmd.ListMatches()
  local linestart = vim_api.nvim_buf_get_lines(listbuf, 0, 1, true)[1] == "" and 0 or -1
  vim_fn.win_execute(listwin,
    [[call nvim_buf_set_lines(0, ]] .. linestart .. [[, -1, 0, ["_ _ pattern"]) | exe "normal! G02wv$\<c-g>"]])
end

return M
