#!/usr/bin/env lua

local setline = vim.fn.setline
local getline = vim.fn.getline
local vim_fn = vim.fn
local vim_api = vim.api
local vim_cmd = vim.cmd

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

_H.upward = function(lineno, here)
  _H.append_to_3_lines_above(lineno)

  lineno = lineno + (M.config.lang_num + 1)
  local last_lineno = vim_fn.line("$")

  local soft_last_lineno = math.min(last_lineno, lineno + 300 * (M.config.lang_num + 1))
  while lineno <= soft_last_lineno do
    setline(lineno - (M.config.lang_num + 1), getline(lineno))
    lineno = lineno + (M.config.lang_num + 1)
  end

  vim_api.nvim_win_set_cursor(0, here)
  if vim_api.nvim__redraw ~= nil then
    vim_api.nvim__redraw({ win = 0, cursor = true })
    vim_cmd "redraw"
  end

  while lineno <= last_lineno do
    setline(lineno - (M.config.lang_num + 1), getline(lineno))
    lineno = lineno + (M.config.lang_num + 1)
  end

  setline(lineno - (M.config.lang_num + 1), "")
end

---Push current line up to the chunk above, joining to the end of its counterpart
---@param a table
M.cmd.PushUp = function(a)
  local here, lineno
  if type(a) == "table" and type(a.lineno) == "number" then
    lineno = a.lineno
    here = { lineno, 1 }
  else
    here = vim_api.nvim_win_get_cursor(0)
    lineno = here[1]
  end

  if lineno < (M.config.lang_num + 1) or lineno % (M.config.lang_num + 1) == 0 then return end

  _H.upward(lineno, here)
  _H.delete_trailing_empty_lines()
  if M.config.auto_save then vim_cmd("w") end
end

---Pull the counterpart line from the chunk below up to the end of current line
---@param a table
M.cmd.PullBelow = function(a)
  local here, lineno
  if type(a) == "table" and type(a.lineno) == "number" then
    lineno = a.lineno
    here = { lineno, 1 }
  else
    here = vim_api.nvim_win_get_cursor(0)
    lineno = here[1]
  end

  if lineno < (M.config.lang_num + 1) or lineno % (M.config.lang_num + 1) == 0 then return end

  _H.upward(lineno + (M.config.lang_num + 1), here)
  _H.delete_trailing_empty_lines()
  if M.config.auto_save then vim_cmd("w") end
end

---Helper for PushUpPair and PullBelowPair
---@param lineno integer
---@param here integer[]
_H.upward_pair = function(lineno, here)
  -- locate first chunk line
  lineno = lineno - lineno % (M.config.lang_num + 1)

  for offset = 1, M.config.lang_num do _H.append_to_3_lines_above(lineno + offset) end

  lineno = lineno + (M.config.lang_num + 1)
  local last_lineno = vim_fn.line("$")

  local soft_last_lineno = math.min(last_lineno, lineno + 300 * (M.config.lang_num + 1))
  while lineno <= soft_last_lineno do
    for offset = 1, M.config.lang_num do
      setline((lineno + offset) - (M.config.lang_num + 1), getline(lineno + offset))
    end
    lineno = lineno + (M.config.lang_num + 1)
  end

  vim_api.nvim_win_set_cursor(0, here)
  if vim_api.nvim__redraw ~= nil then
    vim_api.nvim__redraw({ win = 0, cursor = true })
    vim_cmd "redraw"
  end

  while lineno <= last_lineno do
    for offset = 1, M.config.lang_num do
      setline((lineno + offset) - (M.config.lang_num + 1), getline(lineno + offset))
    end
    lineno = lineno + (M.config.lang_num + 1)
  end

  for offset = 1, M.config.lang_num do
    setline((lineno + offset) - (M.config.lang_num + 1), "")
  end
end

---Push current chunk up to the one above, joining each line to the end of the corresponding counterpart
M.cmd.PushUpPair = function()
  local here = vim_api.nvim_win_get_cursor(0)

  local lineno = here[1]
  if lineno <= (M.config.lang_num + 1) then return end

  _H.upward_pair(lineno, here)

  _H.delete_trailing_empty_lines()
  if M.config.auto_save then vim_cmd("w") end
end

---Pull the chunk below up to current chunk, joining each line to the end of the corresponding line
M.cmd.PullBelowPair = function()
  local here = vim_api.nvim_win_get_cursor(0)

  local lineno = here[1] + (M.config.lang_num + 1)
  if vim_fn.line("$") - lineno <= (M.config.lang_num) then return end

  _H.upward_pair(lineno, here)

  _H.delete_trailing_empty_lines()
  if M.config.auto_save then vim_cmd("w") end
end

---Push the text on the right side of the cursor in the current line down to the chunk below
M.cmd.PushDownRightPart = function(lnum)
  local curr_lineno = lnum or vim_fn.line(".")
  if curr_lineno % (M.config.lang_num + 1) == 0 then return end

  local last_lineno = vim_fn.line("$")
  for _ = 1, M.config.lang_num + 1 do vim_fn.append(last_lineno, "") end
  local last_counterpart_lineno = last_lineno - (last_lineno - curr_lineno) % (M.config.lang_num + 1)
  local soft_last_counterpart_lineno = math.min(last_counterpart_lineno, curr_lineno + 300 * (M.config.lang_num + 1))
  local lineno = soft_last_counterpart_lineno - (M.config.lang_num + 1)
  local cache_line = getline(soft_last_counterpart_lineno)

  while lineno > curr_lineno do
    setline(lineno + (M.config.lang_num + 1), getline(lineno))
    lineno = lineno - (M.config.lang_num + 1)
  end

  local curr_line = getline(curr_lineno)
  local cursor_col = vim_fn.col(".")
  local before_cursor = curr_line:sub(1, cursor_col - 1)
  local after_cursor = curr_line:sub(cursor_col)
  before_cursor = before_cursor:gsub([[%s+$]], "", 1)
  after_cursor = after_cursor:gsub([[^%s+]], "", 1)
  local languid = tostring(curr_lineno % (M.config.lang_num + 1))
  local sep = M.config.language_separator[languid]
  before_cursor = vim_fn.substitute(before_cursor, vim_fn.escape(sep, [[\]]) .. [[$]], "", "")
  after_cursor = vim_fn.substitute(after_cursor, [[^]] .. vim_fn.escape(sep, [[\]]), "", "")
  setline(curr_lineno, before_cursor)
  setline(curr_lineno + (M.config.lang_num + 1), after_cursor)

  if vim_api.nvim__redraw ~= nil then
    vim_api.nvim__redraw({ win = 0, cursor = true })
    vim_cmd "redraw"
  end

  lineno = last_counterpart_lineno
  while lineno > soft_last_counterpart_lineno do
    setline(lineno + (M.config.lang_num + 1), getline(lineno))
    lineno = lineno - (M.config.lang_num + 1)
  end
  setline(soft_last_counterpart_lineno + (M.config.lang_num + 1), cache_line)

  _H.delete_trailing_empty_lines()
  if M.config.auto_save then vim_cmd("w") end
end

---Push current line down to the chunk below
M.cmd.PushDown = function(lineno)
  vim_cmd([[normal! 0]])
  M.cmd.PushDownRightPart(lineno)
end

---@param lnum integer
M.cmd.LeaveAlone = function(lnum)
  curr_lineno = lnum or vim_fn.line(".")
  local languid = curr_lineno % (M.config.lang_num + 1)
  if languid == 0 then return end

  local last_lineno = vim_fn.line("$")
  for _ = 1, M.config.lang_num + 1 do vim_fn.append(last_lineno, "") end

  local last_chunk_prev_lineno = last_lineno - last_lineno % (M.config.lang_num + 1)
  local curr_chunk_prev_lineno = curr_lineno - languid
  local soft_last_chunk_prev_lineno = math.min(last_chunk_prev_lineno,
    curr_chunk_prev_lineno + 300 * (M.config.lang_num + 1))
  local lineno = soft_last_chunk_prev_lineno - (M.config.lang_num + 1)
  local cache_lines = vim_api.nvim_buf_get_lines(0, soft_last_chunk_prev_lineno,
    soft_last_chunk_prev_lineno + (M.config.lang_num + 1), false)

  while lineno > curr_chunk_prev_lineno do
    for offset = 1, M.config.lang_num do
      if offset ~= languid then setline((lineno + offset) + (M.config.lang_num + 1), getline(lineno + offset)) end
    end
    lineno = lineno - (M.config.lang_num + 1)
  end
  for offset = 1, M.config.lang_num do
    if offset ~= languid then setline(lineno + offset, "-") end
  end

  M.cmd.NavigateDown()
  if vim_api.nvim__redraw ~= nil then
    vim_api.nvim__redraw({ win = 0, cursor = true })
    vim_cmd "redraw"
  end

  lineno = last_chunk_prev_lineno
  while lineno > soft_last_chunk_prev_lineno do
    for offset = 1, M.config.lang_num do
      if offset ~= languid then setline((lineno + offset) + (M.config.lang_num + 1), getline(lineno + offset)) end
    end
    lineno = lineno - (M.config.lang_num + 1)
  end
  for offset = 1, M.config.lang_num do
    if offset ~= languid then
      setline((soft_last_chunk_prev_lineno + offset) + (M.config.lang_num + 1),
        cache_lines[offset])
    end
  end

  _H.delete_trailing_empty_lines()
end

---Move cursor to the chunk below at the counterpart of current line
M.cmd.NavigateDown = function()
  vim_cmd([[normal! 0]] .. (M.config.lang_num + 1) .. "j")
end

---Move cursor to the chunk above at the counterpart of current line
M.cmd.NavigateUp = function()
  vim_cmd([[normal! 0]] .. (M.config.lang_num + 1) .. "k")
end

---:[range]ItDeInterlace, works on the whole buffer if range is not provided
---upper- and lower-most empty lines are ignored
---requires the range is paired, [(, L2_1), (L1_2, L2_2), (L1_3, L2_3), ...] will make the buffer chaotic
---@param a table
M.cmd.DeInterlace = function(a)
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

  local num = #a.fargs == 1 and tonumber(a.fargs[1]) or M.config.lang_num

  -- {start} is zero-based, thus (a.line1 - 1) and (a.line2 - 1)
  -- {end} is exclusive, thus (a.line2 - 1 + 1), thus a.line2
  local lines = vim_api.nvim_buf_get_lines(buf, a.line1 - 1, a.line2, false)
  local len_lines = #lines

  local results = {}
  -- gather lines from each language and append to {results}
  for offset = 1, num do
    for chunkno = 0, len_lines - offset, num + 1 do
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

---Insert a newline at end of each Chinese sentence boundaries
---@param a table
---@return nil
M.cmd.SplitChineseSentences = function(a)
  -- :h split()
  -- Use '\zs' at the end of the pattern to keep the separator.
  -- :echo split('bar:foo', ':\zs')
  local regex = [[\v[…。!！?？]+[”"’'）)】]*\zs]]
  _H.SplitHelper(regex, a)
end

---Insert a newline at end of each English sentence boundaries
---@param a table
---@return nil
M.cmd.SplitEnglishSentences = function(a)
  local regex = [[\v%(%(%(<al)@<!%(\u\l{,2})@<!(\.\a)@<!\.|[!?])+['’"”]?)%(\s|$)\zs]]
  _H.SplitHelper(regex, a)
end

---:[range]ItInterlace [lang_num]
---Works on the whole buffer when range is not provided. Uses config.lang_num when lang_num is not provided.
---Empty lines are filtered out before the interlacement.
---@param a table
---@return nil
M.cmd.Interlace = function(a)
  -- {start} is zero-based, thus (a.line1 - 1) and (a.line2 - 1)
  -- {end} is exclusive, thus (a.line2 - 1 + 1), thus a.line2
  local lines = vim.tbl_filter(function(s) return s ~= "" end,
    vim_api.nvim_buf_get_lines(0, a.line1 - 1, a.line2, false))
  local lang_num = #a.fargs == 1 and tonumber(a.fargs[1]) or M.config.lang_num

  local chunk_count = math.floor(#lines / lang_num)
  local remainder = #lines % lang_num
  local result = {}

  for i = 1, chunk_count do
    for j = 1, lang_num do
      table.insert(result, lines[i + chunk_count * (j - 1)])
    end
    table.insert(result, "")
  end

  for i = 1, remainder do
    table.insert(result, lines[chunk_count * lang_num + i])
  end

  vim_api.nvim_buf_set_lines(0, a.line1 - 1, a.line2, false, result)
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
  local count
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
  local lineno_orig = vim_fn.line(".")
  -- Add `direction * (lang_num + 1)` to start searching from the next chunk.
  -- This prevents the cursor from remaining on the same unaligned chunk if the
  -- function is called multiple times. If a search returns a false positive
  -- and places the cursor on an aligned chunk, calling this function again
  -- allows the cursor to move forward instead of staying.
  local lineno = lineno_orig + direction * (M.config.lang_num + 1)
  -- locate first line of the nearest chunk below/above and start search from there
  while lineno % (M.config.lang_num + 1) ~= 1 do lineno = lineno + direction end
  local lastline = direction == 1 and vim_fn.line("$") or 1

  local chunk_lines
  local group_count1, group_count2
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
          vim_cmd "normal! zz"
          logger.info("Jumped over " .. math.abs(l - lineno_orig) .. " lines")
          return
        end
        for k1, _ in pairs(group_count1) do
          if group_count2[k1] == nil then
            vim_api.nvim_win_set_cursor(0, { l, 1 })
            vim_cmd "normal! zz"
            logger.info("Jumped over " .. math.abs(l - lineno_orig) .. " lines")
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
