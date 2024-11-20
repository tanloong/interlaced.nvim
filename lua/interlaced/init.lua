#!/usr/bin/env lua

local keyset = vim.keymap.set
local setline = vim.fn.setline
local getline = vim.fn.getline
local vim_fn = vim.fn
local vim_api = vim.api
local vim_cmd = vim.cmd
local vim_uv = vim.uv or vim.loop
local create_command = vim_api.nvim_create_user_command

local config = require("interlaced.config")
local highlights = require("interlaced.highlights")

-- NOTE: Develop test mode !!
require("interlaced.test")

local _H = {}
local M = {
  _H = _H,
  _Name = "Interlaced",
  _orig_mappings = {},
  _is_mappings_set = false,
  _is_matches_on = true,
  _matches = {},
  -- A list of regex patterns (named entities, numbers, dates, etc) users want to highlight
  -- :h matchadd()
  -- Matching is case sensitive and magic, unless case sensitivity
  -- or magicness are explicitly overridden in {pattern}.  The
  config = {},
  cmd = {},
}

---@param msg string # message to log
---@param kind string # hl group to use for logging
---@param history boolean # whether to add the message to history
M._log = function(msg, kind, history)
  vim.schedule(function()
    vim_api.nvim_echo({
      { M._Name .. ": " .. msg, kind },
    }, history, {})
  end)
end

-- nicer error messages using nvim_echo
---@param msg string # error message
M.error = function(msg)
  M._log(msg, "ErrorMsg", true)
end

-- nicer warning messages using nvim_echo
---@param msg string # warning message
M.warning = function(msg)
  M._log(msg, "WarningMsg", true)
end

-- nicer plain messages using nvim_echo
---@param msg string # plain message
M.info = function(msg)
  M._log(msg, "Normal", true)
end

_H.append_to_3_lines_above = function(lineno)
  local lineno_target = lineno - (M.config.lang_num + 1)
  local line = getline(lineno)
  local line_target = getline(lineno_target)

  local languid = tostring(lineno % (M.config.lang_num + 1))
  local sep = M.config.language_separator[languid]
  setline(lineno_target, line_target:gsub("%s+$", "") .. sep .. line)
  setline(lineno, "")
end

_H.delete_trailing_empty_lines = function()
  local last_lineno = vim_fn.line("$")
  local buf = vim_api.nvim_get_current_buf()
  while getline(last_lineno):match("^%s*$") do
    vim_fn.deletebufline(buf, last_lineno)
    last_lineno = last_lineno - 1
  end
end

M.cmd.MapInterlaced = function()
  if M._is_mappings_set then
    M.warning("Keybindings already on, nothing to do")
    return
  end
  for func, shortcut in pairs(M.config.mappings) do
    _H.store_orig_mapping(shortcut)
    keyset("n", shortcut, M.cmd[func], { noremap = true, buffer = true, nowait = true })
  end
  M.info("Keybindings on")
  M._is_mappings_set = true
end

M.cmd.UnmapInterlaced = function()
  if not M._is_mappings_set then
    M.warning("Keybindings already off, nothing to do")
    return
  end
  for keystroke, mapping in pairs(M._orig_mappings) do
    if vim.tbl_isempty(mapping) then
      vim_api.nvim_buf_del_keymap(0, "n", keystroke)
    else
      mapping.buffer = true
      vim_fn.mapset("n", false, mapping)
    end
  end
  M.info("Keybindings off")
  M._is_mappings_set = false
end

M.cmd.PushUp = function()
  local lineno = vim_fn.line(".")
  if lineno <= (M.config.lang_num + 1) then
    M.warning("Pushing too early, please move down your cursor.")
    return
  end

  _H.append_to_3_lines_above(lineno)

  lineno = lineno + (M.config.lang_num + 1)
  local last_lineno = vim_fn.line("$")
  while lineno <= last_lineno do
    setline(lineno - (M.config.lang_num + 1), getline(lineno))
    lineno = lineno + (M.config.lang_num + 1)
  end
  setline(lineno - (M.config.lang_num + 1), "")

  _H.delete_trailing_empty_lines()
  if M.config.auto_save then
    vim_cmd("w")
  end
end

M.cmd.PushUpPair = function()
  local here = vim_fn.getpos(".")
  vim_cmd([[normal! {]])
  for _ = 1, 2 do
    vim_fn.setcursorcharpos(vim_fn.line(".") + 1, 1)
    M.cmd.PushUp()
  end
  vim_fn.setpos(".", here)
end

M.cmd.PullUp = function()
  local here = vim_fn.getpos(".")
  local curr_lineno = here[2]
  local last_lineno = vim_fn.line("$")
  if last_lineno - curr_lineno < (M.config.lang_num + 1) then
    M.warning("No more lines can be pulled up.")
    return
  end

  vim_fn.setcursorcharpos(curr_lineno + (M.config.lang_num + 1), 1)
  M.cmd.PushUp()
  vim_fn.setpos(".", here)
end

M.cmd.PullUpPair = function()
  local here = vim_fn.getpos(".")
  local curr_lineno = here[2]
  local last_lineno = vim_fn.line("$")
  if last_lineno - curr_lineno < (M.config.lang_num + 1) + 1 then
    M.warning("No more lines can be pulled up.")
    return
  end

  vim_cmd([[normal! }]])
  for _ = 1, 2 do
    vim_fn.setcursorcharpos(vim_fn.line(".") + 1, 1)
    M.cmd.PushUp()
  end
  vim_fn.setpos(".", here)
end

M.cmd.PushDownRightPart = function()
  local lineno = vim_fn.line(".")
  local last_lineno = vim_fn.line("$")

  vim_fn.append(last_lineno, { "", "", "" })

  local last_counterpart_lineno = last_lineno
  while (last_counterpart_lineno - lineno) % (M.config.lang_num + 1) ~= 0 do
    last_counterpart_lineno = last_counterpart_lineno - 1
  end

  for i = last_counterpart_lineno, lineno + (M.config.lang_num + 1), -(M.config.lang_num + 1) do
    setline(i + (M.config.lang_num + 1), getline(i))
  end

  local curr_line = getline(lineno)
  local cursor_col = vim_fn.col(".")

  local before_cursor = curr_line:sub(1, cursor_col - 1)
  local after_cursor = curr_line:sub(cursor_col)
  before_cursor = vim_fn.substitute(before_cursor, [[\s\+$]], "", "")
  after_cursor = vim_fn.substitute(after_cursor, [[^\s\+]], "", "")

  local languid = tostring(lineno % (M.config.lang_num + 1))
  local sep = M.config.language_separator[languid]
  before_cursor = vim_fn.substitute(before_cursor, vim_fn.escape(sep, [[\]]) .. [[$]], "", "")
  after_cursor = vim_fn.substitute(after_cursor, [[^]] .. vim_fn.escape(sep, [[\]]), "", "")

  setline(lineno, before_cursor)
  setline(lineno + (M.config.lang_num + 1), after_cursor)

  _H.delete_trailing_empty_lines()
  if M.config.auto_save then
    vim_cmd("w")
  end
end

M.cmd.PushDown = function()
  vim_cmd([[normal! 0]])
  M.cmd.PushDownRightPart()
end

M.cmd.SetSeparator = function(a)
  -- :ItSetSeparator ?
  -- :ItSetSeparator
  if #a.fargs == 0 or a.args == "?" then
    for _, l in ipairs(vim_fn.sort(vim.tbl_keys(M.config.language_separator))) do
      vim.print("L" .. l .. ": '" .. M.config.language_separator[l] .. "'")
    end
    return
  end

  -- :ItSetSeparator {int} {str}
  if #a.fargs ~= 2 then
    M.error("Expected 2 arguments, got " .. #a.fargs)
    return
  end
  local l = a.fargs[1]
  local sep = a.fargs[2]

  -- :ItSetSeparator {int} ''
  -- :ItSetSeparator {int} ""
  if sep == [['']] or sep == [[""]] then
    sep = ""
    -- :ItSetSeparator {int} \t
  elseif sep == [[\t]] then
    sep = "\t"
  end

  M.config.language_separator[tostring(l)] = sep
  vim.print("L" .. l .. " separator: '" .. sep .. "'")
end

M.cmd.ListSeparators = function()
end

M.cmd.SetLangNum = function(a)
  -- :ItSetLangNum ?
  -- :ItSetLangNum
  if #a.fargs == 0 or a.args == "?" then
    vim.print("Language number: " .. M.config.lang_num)
    return
  end

  -- :ItSetLangNum {int}
  local n = tonumber(a.args)
  M.config.lang_num = n

  while #M.config.language_separator < n do
    table.insert(M.config.language_separator, " ")
  end
  vim.print("Language number: " .. M.config.lang_num)
end

M.cmd.NavigateDown = function()
  vim_cmd([[normal! 0]] .. (M.config.lang_num + 1) .. "j")
end

M.cmd.NavigateUp = function()
  vim_cmd([[normal! 0]] .. (M.config.lang_num + 1) .. "k")
end

---@param lines1 (string|nil)[]
---@param lines2 (string|nil)[]
---@return string[]
_H.zip = function(lines1, lines2)
  local lines = {}
  local len1, len2 = #lines1, #lines2
  local len_max = math.max(len1, len2)
  for i = 1, len_max do
    table.insert(lines, lines1[i] or "")
    table.insert(lines, lines2[i] or "")
    table.insert(lines, "")
  end
  return lines
end

---@return string
_H.get_timestr = function()
  local timestr = os.date("%Y-%m-%d.%H-%M-%S")
  local stamp = tostring(math.floor(vim_uv.hrtime() / 1000000) % 1000)
  while #stamp < 3 do
    stamp = "0" .. stamp
  end
  return timestr .. "." .. stamp
end

---@param params table
---@param is_curbuf_L1 boolean
---@return nil
_H.InterlaceWithL = function(params, is_curbuf_L1)
  local filepath = params.args
  local fh, err = io.open(filepath, "r")
  if not fh then
    M.warning("Failed to open file for reading: " .. filepath .. "\nError: " .. err)
    return nil
  end
  local lines_that = {}
  for line in fh:lines() do
    table.insert(lines_that, line)
  end
  fh:close()
  local lines_this = vim_api.nvim_buf_get_lines(0, 0, -1, true)
  lines_this = vim.tbl_filter(function(s) return s:find("%S") ~= nil end, lines_this)
  lines_that = vim.tbl_filter(function(s) return s:find("%S") ~= nil end, lines_that)
  local lines = is_curbuf_L1 and _H.zip(lines_this, lines_that) or _H.zip(lines_that, lines_this)
  local time = _H.get_timestr()
  local interlaced_path = time .. ".interlaced.txt"
  vim_fn.writefile(lines, interlaced_path)
  vim_cmd("edit " .. interlaced_path)
  if not M._is_mappings_set then
    M.cmd.MapInterlaced()
  end
end

---@param params table
---@return nil
M.cmd.InterlaceWithL1 = function(params)
  _H.InterlaceWithL(params, false)
end

---@param params table
---@return nil
M.cmd.InterlaceWithL2 = function(params)
  _H.InterlaceWithL(params, true)
end

M.cmd.Deinterlace = function(a)
  -- 0 does not indicate current buffer to deletebufline(), has to use nvim_get_current_buf()
  local buf = vim_api.nvim_get_current_buf()

  -- {start} is zero-based, thus (a.line1 - 1) and (a.line2 - 1)
  -- {end} is exclusive, thus (a.line2 - 1 + 1), thus a.line2
  local lines = vim_api.nvim_buf_get_lines(buf, a.line1 - 1, a.line2, false)

  -- remove leading and trailing empty lines
  while lines[#lines] == "" do
    table.remove(lines)
  end
  while lines[1] == "" do
    table.remove(lines, 1)
  end

  local results = {}
  -- gather lines from each language and append to {results}
  for offset = 1, M.config.lang_num, 1 do
    for chunkno = 0, #lines - offset, (M.config.lang_num + 1) do
      table.insert(results, lines[chunkno + offset])
    end
    -- for each language, append an empty string to {results} after gathering
    table.insert(results, "")
  end
  vim_api.nvim_buf_set_lines(buf, a.line1 - 1, a.line2, true, results)
end

---@param regex string
---@param a table
---@return nil
_H.SplitHelper = function(regex, a)
  -- cmd([[saveas! %.splitted]])
  local buf = vim_api.nvim_get_current_buf()
  for i = a.line2, a.line1, -1 do
    line = getline(i)
    local sents = vim_fn.split(line, regex)

    if #sents > 1 then
      vim_fn.deletebufline(buf, i)
      vim_fn.append(i - 1, sents)
    end
  end
  if M.config.auto_save then
    vim_cmd("w")
  end
end

---@param a table
---@return nil
M.cmd.SplitChineseSentences = function(a)
  -- :h split()
  -- Use '\zs' at the end of the pattern to keep the separator.
  -- :echo split('bar:foo', ':\zs')
  local regex = [[\v[…。!！?？]+[”"’'）)】]*\zs]]
  _H.SplitHelper(regex, a)
end

---@param a table
---@return nil
M.cmd.SplitEnglishSentences = function(a)
  local regex = [[\v%(%(%(<al)@<!%(\u\l{,2})@<!(\.\a)@<!\.|[!?])+['’"”]?)%(\s|$)\zs]]
  _H.SplitHelper(regex, a)
end

---@param a table
---@return nil
M.cmd.Interlace = function(a)
  local x, y
  local arg_count = #a.fargs

  if arg_count == 0 then
    x, y = 1, 1
  elseif arg_count == 1 then
    x, y = tonumber(a.fargs[1]), tonumber(a.fargs[1])
  elseif arg_count == 2 then
    x, y = tonumber(a.fargs[1]), tonumber(a.fargs[2])
  else
    M.warning("Argument Error: can have at most 2 arguments")
  end

  local i = a.line1 + x - 1
  local total = a.line2 - a.line1 + 1
  local j = math.floor(total / (x + y)) * x + a.line1

  while j < a.line2 do
    local range = y > 1 and j .. "," .. (j + y) or j
    vim.cmd(range .. "move " .. i)
    i = i + y + x
    j = j + y
  end
end

M.cmd.Dump = function(a)
  local path = nil
  -- a.args == nil: the BufWinLeave autocmd below calls this func without args
  if a.args == nil or #a.args == 0 then
    path = vim.fs.joinpath(vim_fn.expand("%:h"), ".interlaced.json")
  else
    path = a.args
  end
  local data = { curpos = vim_fn.getpos("."), matches = vim_fn.getmatches(), config = M.config }
  -- the json string will be written to the frist line
  pcall(vim.fn.writefile, { vim.json.encode(data) }, path, "")
end

M.cmd.Load = function(a)
  local path = nil
  if #a.args == 0 then
    path = vim.fs.joinpath(vim_fn.expand("%:h"), ".interlaced.json")
  else
    path = a.args
  end

  -- read only the first line
  local ok, ret = pcall(vim.fn.readfile, path, "", 1)
  -- ret is a list that contains only the json string element
  if not ok then return end

  ok, ret = pcall(vim.json.decode, ret[1])
  if not ok then return end

  if ret.curpos ~= nil then
    vim_fn.setpos(".", ret.curpos)
  end
  if ret.matches ~= nil then
    vim_fn.setmatches(ret.matches)
  end
  if ret.config ~= nil then
    M.config = vim.tbl_deep_extend("force", M.config, ret.config)
  end
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

M.cmd.ClearMatches = function()
  vim_fn.clearmatches()
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

M.cmd.ListHighlights = function()
  vim.cmd([[filter /\v^]] .. highlights.group_prefix .. "/ highlight")
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
  highlights.highlight(color, patterns)
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
  highlights.highlight(color, patterns)
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

---@param shortcut string
---@return nil
_H.store_orig_mapping = function(shortcut)
  mapping = vim_fn.maparg(shortcut, "n", false, true)
  M._orig_mappings[shortcut] = mapping
end

---@param opts table
---@return nil
M.setup = function(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    M.error(string.format("setup() expects table, but got %s:\n%s", type(opts), vim.inspect(opts)))
    opts = {}
  end
  M.config = vim.tbl_deep_extend("force", config, opts)

  if M.config.setup_mappings_now then
    M.cmd.MapInterlaced()
  end

  -- create commands
  -- :h lua-guide-commands-create
  create_command(M.config.cmd_prefix .. "ClearMatches", M.cmd.ClearMatches,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "Deinterlace", M.cmd.Deinterlace,
    { nargs = 0, range = "%" })
  create_command(M.config.cmd_prefix .. "Dump", M.cmd.Dump,
    { complete = "file", nargs = "?" })
  create_command(M.config.cmd_prefix .. "Interlace", M.cmd.Interlace,
    { nargs = "*", range = "%" })
  create_command(M.config.cmd_prefix .. "InterlaceWithL1", M.cmd.InterlaceWithL1,
    { complete = "file", nargs = 1 })
  create_command(M.config.cmd_prefix .. "InterlaceWithL2", M.cmd.InterlaceWithL2,
    { complete = "file", nargs = 1 })
  create_command(M.config.cmd_prefix .. "ListHighlights", M.cmd.ListHighlights,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "ListMatches", M.cmd.ListMatches,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "ToggleMatches", M.cmd.ToggleMatches,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "Load", M.cmd.Load,
    { complete = "file", nargs = "?" })
  create_command(M.config.cmd_prefix .. "MapInterlaced", M.cmd.MapInterlaced,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "MatchAdd", M.cmd.MatchAdd,
    { complete = "highlight", nargs = "*", range = true })
  create_command(M.config.cmd_prefix .. "MatchAddVisual", M.cmd.MatchAddVisual,
    { complete = "highlight", nargs = "*", range = true })
  create_command(M.config.cmd_prefix .. "MatchDelete", M.cmd.MatchDelete,
    {
      nargs = "?",
      complete = function(ArgLead, CmDLine, CursorPos)
        return vim.tbl_map(function(t) return tostring(t.id) end, vim_fn.getmatches())
      end,
    })
  create_command(M.config.cmd_prefix .. "NavigateDown", M.cmd.NavigateDown,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "NavigateUp", M.cmd.NavigateUp,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PullUp", M.cmd.PullUp,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PullUpPair", M.cmd.PullUpPair,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PushDown", M.cmd.PushDown,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PushDownRightPart", M.cmd.PushDownRightPart,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PushUp", M.cmd.PushUp,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PushUpPair", M.cmd.PushUpPair,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "SetSeparator", M.cmd.SetSeparator, { nargs = "*" })
  create_command(M.config.cmd_prefix .. "SetLangNum", M.cmd.SetLangNum, { nargs = "?" })
  create_command(M.config.cmd_prefix .. "SplitChineseSentences", M.cmd.SplitChineseSentences,
    { nargs = 0, range = "%" })
  create_command(M.config.cmd_prefix .. "SplitEnglishSentences", M.cmd.SplitEnglishSentences,
    { nargs = 0, range = "%" })
  create_command(M.config.cmd_prefix .. "UnmapInterlaced", M.cmd.UnmapInterlaced,
    { nargs = 0 })

  M.info("started")
end

return M
