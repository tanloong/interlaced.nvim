#!/usr/bin/env lua

local keyset = vim.keymap.set
local setline = vim.fn.setline
local getline = vim.fn.getline
local vim_fn = vim.fn
local vim_api = vim.api
local vim_cmd = vim.cmd
local vim_uv = vim.uv or vim.loop
local create_command = vim_api.nvim_create_user_command

local mt = require("interlaced.match")
local logger = require("interlaced.logger")

local _H = {}
local M = {
  _H = _H,
  config = nil,
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

M.cmd.PushUp = function(lineno)
  lineno = lineno or vim_fn.line(".")
  if lineno <= (M.config.lang_num + 1) then
    logger.warning("Pushing too early, please move down your cursor.")
    return
  end
  if lineno % (M.config.lang_num + 1) == 0 then
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

  local lineno = here[1]
  while lineno % (M.config.lang_num + 1) ~= 0 do
    lineno = lineno - 1
  end

  for offset = 1, M.config.lang_num do
    M.cmd.PushUp(lineno + offset)
  end

  vim_api.nvim_win_set_cursor(0, here)
end

M.cmd.PullBelow = function(lineno)
  local here = vim_api.nvim_win_get_cursor(0)
  lineno = lineno or here[1]

  M.cmd.PushUp(lineno + M.config.lang_num + 1)
  vim_api.nvim_win_set_cursor(0, here)
end

M.cmd.PullBelowPair = function()
  local here = vim_api.nvim_win_get_cursor(0)
  local lineno = here[1]

  while lineno % (M.config.lang_num + 1) ~= 0 do
    lineno = lineno + 1
  end

  for offset = 1, M.config.lang_num do
    M.cmd.PushUp(lineno + offset)
  end

  vim_api.nvim_win_set_cursor(0, here)
end

M.cmd.PushDownRightPart = function()
  local lineno = vim_fn.line(".")
  local last_lineno = vim_fn.line("$")

  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "", "", "" })

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
  local len_max = math.max(#lines1, #lines2)
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
    M.cmd.EnableKeybindings()
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
  for i = a.line2, a.line1, -1 do
    local sents = vim_fn.split(getline(i), regex)

    if #sents > 1 then
      vim_api.nvim_buf_set_lines(0, i - 1, i, true, sents)
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
  for pat, id_grp_prio in pairs(mt._matches) do
    count = _H.match_count(line, pat)
    if count > 0 then
      ret[id_grp_prio.group] = count
    end
  end
  return ret
end

---Search the first unaligned chunk below/above current chunk and place the cursor on
---its first line.
---@param direction `1`|`-1`
_H.locate_unaligned = function(direction)
  local buf = vim_api.nvim_get_current_buf()
  -- Add `direction * (lang_num + 1)` to start searching from the next chunk.
  -- This prevents the cursor from remaining on the same unaligned chunk if the
  -- function is called multiple times. If a search returns a false positive
  -- and places the cursor on an aligned chunk, calling this function again
  -- allows the cursor to move forward instead of staying.
  local lineno = vim_fn.line(".") + direction * (M.config.lang_num + 1)
  -- locate first line of the nearest chunk below/above and start search from there
  while lineno % (M.config.lang_num + 1) ~= 1 do lineno = lineno + direction end
  local lastline = direction == 1 and vim_fn.line("$") or 1

  local chunk_lines = nil
  local group_count1, group_count2 = nil, nil
  for l = lineno, lastline, direction * (M.config.lang_num + 1) do
    chunk_lines = vim_api.nvim_buf_get_lines(buf, l - 1, l - 1 + M.config.lang_num, true)
    for i, line1 in ipairs(chunk_lines) do
      group_count1 = _H.group_count(line1)
      -- Note: `vim.iter()` scans table input to decide if it is a list or a dict; to
      -- avoid this cost you can wrap the table with an iterator e.g.
      -- `vim.iter(ipairs({…}))`
      for _, line2 in vim.iter(ipairs(chunk_lines)):skip(i) do
        group_count2 = _H.group_count(line2)

        if vim.tbl_count(group_count1) ~= vim.tbl_count(group_count2) then
          vim_api.nvim_win_set_cursor(0, { l, 1 })
          vim_api.nvim_feedkeys("zz", "n", true)
          return
        end
        for k1, _ in pairs(group_count1) do
          if group_count2[k1] == nil then
            vim_api.nvim_win_set_cursor(0, { l, 1 })
            vim_api.nvim_feedkeys("zz", "n", true)
            return
          end
        end
      end
    end
  end

  vim.print("Not Found")
end

M.cmd.NextUnaligned = function() _H.locate_unaligned(1) end
M.cmd.PrevUnaligned = function() _H.locate_unaligned(-1) end

return M
