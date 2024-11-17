#!/usr/bin/env lua

local keyset = vim.keymap.set
local setline = vim.fn.setline
local getline = vim.fn.getline
local vim_fn = vim.fn
local vim_api = vim.api
local vim_cmd = vim.cmd
local vim_uv = vim.uv or vim.loop
local create_command = vim_api.nvim_create_user_command
local autocmd = vim_api.nvim_create_autocmd
local augroup = vim_api.nvim_create_augroup

local config = require("interlaced.config")
local highlights = require("interlaced.highlights")
local _H = {}
local M = {
  _H = _H,
  _Name = "Interlaced",
  _orig_mappings = {},
  _is_mappings_set = false,
  _patterns = {},
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
  local lineno_minus3 = lineno - 3
  local lineno_minus1 = lineno - 1
  local line = getline(lineno)
  local line_minus3 = getline(lineno_minus3)
  local line_minus1 = getline(lineno_minus1)

  local sep = M.config.separator_L2
  if line_minus1 == "" or line_minus3 == "" then sep = M.config.separator_L1 end
  setline(lineno_minus3, line_minus3:gsub("%s+$", "") .. sep .. line)
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
  if lineno <= 3 then
    M.warning("Pushing too early, please move down your cursor.")
    return
  end

  _H.append_to_3_lines_above(lineno)

  lineno = lineno + 3
  local last_lineno = vim_fn.line("$")
  while lineno <= last_lineno do
    setline(lineno - 3, getline(lineno))
    lineno = lineno + 3
  end
  setline(lineno - 3, "")

  _H.delete_trailing_empty_lines()
  if M.config.auto_save then
    vim_cmd("w")
  end
end

M.cmd.PushUpPair = function()
  local here = vim_fn.getpos(".")
  vim_cmd([[normal! {]])
  for _ = 1, 2 do
    vim_fn.setcursorcharpos({ vim_fn.line(".") + 1, 1 })
    M.cmd.PushUp()
  end
  vim_fn.setpos(".", here)
end

M.cmd.PullUp = function()
  local here = vim_fn.getpos(".")
  local curr_lineno = here[2]
  local last_lineno = vim_fn.line("$")
  if last_lineno - curr_lineno < 3 then
    M.warning("No more lines can be pulled up.")
    return
  end

  vim_fn.setcursorcharpos({ curr_lineno + 3, 1 })
  M.cmd.PushUp()
  vim_fn.setpos(".", here)
end

M.cmd.PullUpPair = function()
  local here = vim_fn.getpos(".")
  local curr_lineno = here[2]
  local last_lineno = vim_fn.line("$")
  if last_lineno - curr_lineno < 3 + 1 then
    M.warning("No more lines can be pulled up.")
    return
  end

  vim_cmd([[normal! }]])
  for _ = 1, 2 do
    vim_fn.setcursorcharpos({ vim_fn.line(".") + 1, 1 })
    M.cmd.PushUp()
  end
  vim_fn.setpos(".", here)
end

M.cmd.PushDownRightPart = function()
  local lineno = vim_fn.line(".")
  local last_lineno = vim_fn.line("$")

  vim_fn.append(last_lineno, { "", "", "" })

  local last_counterpart_lineno = last_lineno
  while (last_counterpart_lineno - lineno) % 3 ~= 0 do
    last_counterpart_lineno = last_counterpart_lineno - 1
  end

  for i = last_counterpart_lineno, lineno + 3, -3 do
    setline(i + 3, getline(i))
  end

  local current_line = getline(lineno)
  local cursor_col = vim_fn.col(".")

  local before_cursor = current_line:sub(1, cursor_col - 1)
  local after_cursor = current_line:sub(cursor_col)

  setline(lineno, vim_fn.substitute(before_cursor, [[\s\+$]], "", ""))
  setline(lineno + 3, vim_fn.substitute(after_cursor, [[^\s\+]], "", ""))

  _H.delete_trailing_empty_lines()
  if M.config.auto_save then
    vim_cmd("w")
  end
end

M.cmd.PushDown = function()
  vim_cmd([[normal! 0]])
  M.cmd.PushDownRightPart()
end

M.cmd.NavigateDown = function()
  vim_cmd([[normal! 03j]])
end

M.cmd.NavigateUp = function()
  vim_cmd([[normal! 03k]])
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
_H.InterlaceWithLx = function(params, is_curbuf_L1)
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
  _H.InterlaceWithLx(params, false)
end

---@param params table
---@return nil
M.cmd.InterlaceWithL2 = function(params)
  _H.InterlaceWithLx(params, true)
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

  -- get lines in l1 and l2
  local lines_l1, lines_l2 = {}, {}
  for i = 1, #lines, 3 do
    table.insert(lines_l1, lines[i])
    table.insert(lines_l2, lines[i + 1])
  end

  -- {start}, {end} is inclusive, used like with getline(), which is 1-based,
  -- thus not (a.line1 - 1)
  vim_fn.deletebufline(buf, a.line1, a.line2)
  vim_fn.append(a.line1 - 1, lines_l1)
  vim_fn.append(a.line1 - 1 + #lines_l1, lines_l2)
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
  local data = { curpos = vim_fn.getpos("."), matches = vim_fn.getmatches() }
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

  vim_fn.setpos(".", ret.curpos)
  vim_fn.setmatches(ret.matches)
end

---@return boolean false if there is no matches to show
M.cmd.ListMatches = function()
  local matches = vim.fn.getmatches()
  if #matches == 0 then
    return false
  end
  for _, m in pairs(matches) do
    -- so dirty :(
    vim.cmd("echon " .. "'id " .. m.id .. "'" ..
      " | echon '\t'" ..
      " | echon " .. "'" .. (m.pattern or "") .. "'" ..
      " | echon '\t'" ..
      " | echohl " .. m.group ..
      " | echon " .. "'" .. m.group .. "'" ..
      " | echohl None" ..
      " | echon '\t'" ..
      " | echon " .. "'priority " .. (m.priority or "") .. "'" ..
      " | echo ''"
    )
  end
  return true
end

M.cmd.ClearMatches = function()
  vim_fn.clearmatches()
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

--:ItMatchDelete print matches an choose one
--:ItMatchDelete . deletes the most recently added match
--:ItMatchDelete n delete match whose id is n
M.cmd.MatchDelete = function(a)
  local id = nil
  if #a.args == 0 then
    ret = M.cmd.ListMatches()
    if not ret then
      return
    end
    id = vim_fn.input({ prompt = "Choose an id: " })
  elseif a.args == "." then
    -- use the id of the most recently added match
    local matches = vim_fn.getmatches()
    if #matches == 0 then
      M.error("No matches to delete")
      return
    end
    id = matches[#matches].id
  else
    id = a.args
  end

  ok, msg = pcall(vim_fn.matchdelete, id)
  if not ok then
    M.error(msg)
    M.cmd.MatchDelete(a)
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
  create_command(M.config.cmd_prefix .. "Load", M.cmd.Load,
    { complete = "file", nargs = "?" })
  create_command(M.config.cmd_prefix .. "MapInterlaced", M.cmd.MapInterlaced,
    { nargs = 0 })
  create_command(M.config.cmd_prefix .. "MatchAdd", M.cmd.MatchAdd,
    { complete = "highlight", nargs = "*", range = true })
  create_command(M.config.cmd_prefix .. "MatchAddVisual", M.cmd.MatchAddVisual,
    { complete = "highlight", nargs = "*", range = true })
  create_command(M.config.cmd_prefix .. "MatchDelete", M.cmd.MatchDelete,
    { nargs = "*", range = true })
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
  create_command(M.config.cmd_prefix .. "SplitChineseSentences", M.cmd.SplitChineseSentences,
    { nargs = 0, range = "%" })
  create_command(M.config.cmd_prefix .. "SplitEnglishSentences", M.cmd.SplitEnglishSentences,
    { nargs = 0, range = "%" })
  create_command(M.config.cmd_prefix .. "UnmapInterlaced", M.cmd.UnmapInterlaced,
    { nargs = 0 })
end

return M
