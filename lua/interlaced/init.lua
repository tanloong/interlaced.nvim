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
local mt = require("interlaced.matches")

-- NOTE: Develop test mode !!
require("interlaced.test")

logger = require("interlaced.logger")

local _H = {}
local M = {
  _H = _H,
  _orig_mappings = {},
  _is_mappings_on = false,
  -- A list of regex patterns (named entities, numbers, dates, etc) users want to highlight
  -- :h matchadd()
  -- Matching is case sensitive and magic, unless case sensitivity
  -- or magicness are explicitly overridden in {pattern}.  The
  config = {},
  cmd = {},
}

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
  if M._is_mappings_on then
    logger.warning("Keybindings already on, nothing to do")
    return
  end
  for func, shortcut in pairs(M.config.mappings) do
    _H.store_orig_mapping(shortcut)
    keyset("n", shortcut, M.cmd[func], { noremap = true, buffer = true, nowait = true })
  end
  logger.info("Keybindings on")
  M._is_mappings_on = true
end

M.cmd.UnmapInterlaced = function()
  if not M._is_mappings_on then
    logger.warning("Keybindings already off, nothing to do")
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
  logger.info("Keybindings off")
  M._is_mappings_on = false
end

M.cmd.PushUp = function()
  local lineno = vim_fn.line(".")
  if lineno <= (M.config.lang_num + 1) then
    logger.warning("Pushing too early, please move down your cursor.")
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
  local here = vim_api.nvim_win_get_cursor(0)
  vim_cmd([[normal! {]])
  for _ = 1, 2 do
    vim_fn.setcursorcharpos(vim_fn.line(".") + 1, 1)
    M.cmd.PushUp()
  end
  vim_api.nvim_win_set_cursor(0, here)
end

M.cmd.PullUp = function()
  local here = vim_api.nvim_win_get_cursor(0)
  local curr_lineno = here[1]
  local last_lineno = vim_fn.line("$")
  if last_lineno - curr_lineno < (M.config.lang_num + 1) then
    logger.warning("No more lines can be pulled up.")
    return
  end

  vim_fn.setcursorcharpos(curr_lineno + (M.config.lang_num + 1), 1)
  M.cmd.PushUp()
  vim_api.nvim_win_set_cursor(0, here)
end

M.cmd.PullUpPair = function()
  local here = vim_api.nvim_win_get_cursor(0)
  local curr_lineno = here[1]
  local last_lineno = vim_fn.line("$")
  if last_lineno - curr_lineno < (M.config.lang_num + 1) + 1 then
    logger.warning("No more lines can be pulled up.")
    return
  end

  vim_cmd([[normal! }]])
  for _ = 1, 2 do
    vim_fn.setcursorcharpos(vim_fn.line(".") + 1, 1)
    M.cmd.PushUp()
  end
  vim_api.nvim_win_set_cursor(0, here)
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
  before_cursor = before_cursor:gsub([[%s+$]], "", 1)
  after_cursor = after_cursor:gsub([[^%s+]], "", 1)

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

M.cmd.SetWeight = function(a)
  -- :ItSetWeight ?
  -- :ItSetWeight
  if #a.fargs == 0 or a.args == "?" then
    for _, l in ipairs(vim_fn.sort(vim.tbl_keys(M.config.language_weight))) do
      vim.print("L" .. l .. ": " .. M.config.language_weight[l])
    end
    return
  end

  -- :ItSetWeight {int} {number}
  if #a.fargs ~= 2 then
    logger.error("Expected 2 arguments, got " .. #a.fargs)
    return
  end

  local l = a.fargs[1]
  local weight = tonumber(a.fargs[2])
  if weight == nil then
    logger.error(a.fargs[2] .. " does not look like a number")
    return
  end

  M.config.language_weight[tostring(l)] = weight
  vim.print("L" .. l .. " weight: " .. weight .. "")
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
    logger.error("Expected 2 arguments, got " .. #a.fargs)
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

  -- default separator when language number grows
  while #M.config.language_separator < n do
    table.insert(M.config.language_separator, " ")
  end
  -- default weight when language number grows
  while #M.config.language_separator < n do
    table.insert(M.config.language_weight, 1)
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
    logger.warning("Failed to open file for reading: " .. filepath .. "\nError: " .. err)
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
  if not M._is_mappings_on then
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

M.cmd.DeInterlace = function(a)
  -- :[range]ItDeInterlace, works on the whole buffer if range is not provided
  -- upper- and lower-most empty lines are ignored
  -- requires the range is paired, [(, L2_1), (L1_2, L2_2), (L1_3, L2_3), ...] will make the buffer chaotic

  -- 0 does not indicate current buffer to deletebufline(), has to use nvim_get_current_buf()
  local buf = vim_api.nvim_get_current_buf()

  -- remove leading and trailing empty lines
  -- matchbufline() returns a list, lua can use next(list) to check empty or not
  while next(vim_fn.matchbufline(buf, '^$', a.line1, a.line1)) do
    a.line1 = a.line1 + 1
  end
  while next(vim_fn.matchbufline(buf, '^$', a.line2, a.line2)) do
    a.line2 = a.line2 - 1
  end

  -- {start} is zero-based, thus (a.line1 - 1) and (a.line2 - 1)
  -- {end} is exclusive, thus (a.line2 - 1 + 1), thus a.line2
  local lines = vim_api.nvim_buf_get_lines(buf, a.line1 - 1, a.line2, false)

  local results = {}
  -- gather lines from each language and append to {results}
  for offset = 1, M.config.lang_num do
    for chunkno = 0, #lines - offset, (M.config.lang_num + 1) do
      if lines[chunkno + offset] ~= "" then
        table.insert(results, lines[chunkno + offset])
      end
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
    logger.warning("Argument Error: can have at most 2 arguments")
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
  local data = { curpos = vim_api.nvim_win_get_cursor(0), matches = vim_fn.getmatches(), config = M.config }
  -- the json string will be written to the frist line
  pcall(vim_fn.writefile, { vim.json.encode(data) }, path, "")
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
    vim_api.nvim_win_set_cursor(0, ret.curpos)
  end
  if ret.matches ~= nil then
    vim_fn.setmatches(ret.matches)
    mt._matches = ret.matches
  end
  if ret.config ~= nil then
    M.config = vim.tbl_deep_extend("force", M.config, ret.config)
  end
end

---@param s string
---@param pat string vim pattern
---@return integer
_H.match_count = function(s, pat)
  local count = 1
  -- :h match()
  while vim.fn.match(s, pat, 0, count) ~= -1 do
    count = count + 1
  end
  return count - 1
end

---@param line string
---@return table<string, integer>
_H.group_count = function(line)
  local ret = {}
  local count = nil
  for _, m in ipairs(mt._matches) do
    count = _H.match_count(line, m.pattern)
    if count > 0 then
      ret[m.group] = count
    end
  end
  return ret
end

M.cmd.JumpToNextUnaligned = function()
  local buf = vim_api.nvim_get_current_buf()
  local lineno = vim_fn.line(".")
  -- locate first line of the nearest chunk below and start search from there
  while lineno % (M.config.lang_num + 1) ~= 1 do lineno = lineno + 1 end
  local lastline = vim_fn.line("$")

  local chunk_lines = nil
  -- local weight1, weight2 = nil, nil
  local group_count1, group_count2 = nil, nil
  for l = lineno, lastline, (M.config.lang_num + 1) do
    chunk_lines = vim_api.nvim_buf_get_lines(buf, l - 1, l - 1 + M.config.lang_num, true)
    -- Note: `vim.iter()` scans table input to decide if it is a list or a dict; to
    -- avoid this cost you can wrap the table with an iterator e.g.
    -- `vim.iter(ipairs({…}))`
    for i, line1 in vim.iter(ipairs(chunk_lines)) do
      -- weight1 = M.config.language_weight[tostring(i)]
      group_count1 = _H.group_count(line1)
      for _, line2 in vim.iter(ipairs(chunk_lines)):skip(i) do
        -- weight2 = M.config.language_weight[tostring(j)]
        group_count2 = _H.group_count(line2)

        if vim.tbl_count(group_count1) ~= vim.tbl_count(group_count2) then
            vim.print(group_count1)
            vim.print(group_count2)
          vim_api.nvim_win_set_cursor(0, { l, 1 })
          vim_api.nvim_feedkeys("zz", "n", true)
          return
        end
        for k1, _ in pairs(group_count1) do
          if group_count2[k1] == nil then
            vim_api.nvim_win_set_cursor(0, { l, 1 })
            vim_api.nvim_feedkeys("zz", "n", true)
            vim.print(group_count1)
            vim.print(group_count2)
            return
          end
        end
        -- if (vim_fn.strcharlen(line1) * weight1 - vim_fn.strcharlen(line2) * weight2 > 0) then
        --   vim_api.nvim_win_set_cursor(0, { l, 1 })
        --   vim_api.nvim_feedkeys("zz", "n", true)
        --   return
        -- end
      end
    end
  end

  vim.print("Not Found")
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
    logger.error(string.format("setup() expects table, but got %s:\n%s", type(opts), vim.inspect(opts)))
    opts = {}
  end
  M.config = vim.tbl_deep_extend("force", config, opts)

  if M.config.setup_mappings_now then
    M.cmd.MapInterlaced()
  end

  -- create commands
  -- :h lua-guide-commands-create
  create_command(M.config.cmd_prefix .. "DeInterlace", M.cmd.DeInterlace, { nargs = 0, range = "%" })
  create_command(M.config.cmd_prefix .. "Dump", M.cmd.Dump, { complete = "file", nargs = "?" })
  create_command(M.config.cmd_prefix .. "Interlace", M.cmd.Interlace, { nargs = "*", range = "%" })
  create_command(M.config.cmd_prefix .. "InterlaceWithL1", M.cmd.InterlaceWithL1, { complete = "file", nargs = 1 })
  create_command(M.config.cmd_prefix .. "InterlaceWithL2", M.cmd.InterlaceWithL2, { complete = "file", nargs = 1 })
  create_command(M.config.cmd_prefix .. "Load", M.cmd.Load, { complete = "file", nargs = "?" })
  create_command(M.config.cmd_prefix .. "MapInterlaced", M.cmd.MapInterlaced, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "NavigateDown", M.cmd.NavigateDown, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "NavigateUp", M.cmd.NavigateUp, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PullUp", M.cmd.PullUp, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PullUpPair", M.cmd.PullUpPair, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PushDown", M.cmd.PushDown, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PushDownRightPart", M.cmd.PushDownRightPart, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PushUp", M.cmd.PushUp, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PushUpPair", M.cmd.PushUpPair, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "SetLangNum", M.cmd.SetLangNum, { nargs = "?" })
  create_command(M.config.cmd_prefix .. "SetSeparator", M.cmd.SetSeparator, { nargs = "*" })
  create_command(M.config.cmd_prefix .. "SetWeight", M.cmd.SetWeight, { nargs = "*" })
  create_command(M.config.cmd_prefix .. "SplitChineseSentences", M.cmd.SplitChineseSentences, { nargs = 0, range = "%" })
  create_command(M.config.cmd_prefix .. "SplitEnglishSentences", M.cmd.SplitEnglishSentences, { nargs = 0, range = "%" })
  create_command(M.config.cmd_prefix .. "UnmapInterlaced", M.cmd.UnmapInterlaced, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "JumpToNextUnaligned", M.cmd.JumpToNextUnaligned, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "ClearMatches", mt.cmd.ClearMatches, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "ListHighlights", mt.cmd.ListHighlights, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "ListMatches", mt.cmd.ListMatches, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "MatchAdd", mt.cmd.MatchAdd, {})
  create_command(M.config.cmd_prefix .. "MatchAddVisual", mt.cmd.MatchAddVisual, { range = true })
  create_command(M.config.cmd_prefix .. "MatchToggle", mt.cmd.MatchToggle, { nargs = 0 })

  logger.info("started")
end

return M
