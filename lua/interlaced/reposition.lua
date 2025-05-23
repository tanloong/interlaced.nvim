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
  _undos = {}, -- store reverse changes of PushUp(Pair), PullBelow(Pair), PushDown(RightPart), LeaveAlone to undo
  _redos = {},
  config = nil,
  cmd = {},
}

-------------------------------RE-POSITION START--------------------------------

---@return integer
_H.append_to_3_lines_above = function(lineno)
  local lineno_target = lineno - (M.config.lang_num + 1)
  local line = getline(lineno)
  local line_target = getline(lineno_target):gsub("%s+$", "")
  local ret = #line_target + 1

  local languid = tostring(lineno % (M.config.lang_num + 1))
  local sep = M.config.language_separator[languid] or ""
  line_target = line_target == "" and line or ("%s%s%s"):format(line_target, sep, line)
  setline(lineno_target, line_target)
  setline(lineno, "")
  return ret
end

_H.delete_trailing_empty_lines = function()
  local last_lineno = vim_api.nvim_buf_line_count(0)
  local buf = vim_api.nvim_get_current_buf()
  while getline(last_lineno):match("^%s*$") do
    vim_fn.deletebufline(buf, last_lineno)
    last_lineno = last_lineno - 1
  end
end

---@param store boolean|nil
_H.push_up = function(lnum, here, store)
  if lnum < (M.config.lang_num + 1) or lnum % (M.config.lang_num + 1) == 0 then return end
  if store == nil then store = true end

  -- temporarily disable undo history recording
  local ul_orig = vim_api.nvim_get_option_value("undolevels", { scope = "local" })
  vim_api.nvim_set_option_value("undolevels", -1, { scope = "local" })

  local cnum = _H.append_to_3_lines_above(lnum)

  local lineno = lnum + (M.config.lang_num + 1)
  local last_lineno = vim_api.nvim_buf_line_count(0)

  local soft_last_lineno = math.min(last_lineno, lineno + 200 * (M.config.lang_num + 1))

  while lineno <= soft_last_lineno do
    setline(lineno - (M.config.lang_num + 1), getline(lineno))
    lineno = lineno + (M.config.lang_num + 1)
  end

  vim_api.nvim_win_set_cursor(0, here)
  if vim_api.nvim__redraw ~= nil then
    vim_api.nvim__redraw({ win = 0, flush = true })
    -- fix the screen is not updated to respect `scrolloff` when cursor is at
    -- bottom joining a line from below that occupies multiple screen-lines.
    vim_cmd "normal! jk"
    vim_api.nvim__redraw({ win = 0, cursor = true, flush = true })
  end

  while lineno <= last_lineno do
    setline(lineno - (M.config.lang_num + 1), getline(lineno))
    lineno = lineno + (M.config.lang_num + 1)
  end

  setline(lineno - (M.config.lang_num + 1), "")

  _H.delete_trailing_empty_lines()

  if store then
    _H.store_undo {
      function() _H.push_up(lnum, here, false) end,
      function() _H.push_down_right_part(lnum - (M.config.lang_num + 1), cnum, false) end,
    }
    M._redos = {}
  end

  -- enable undo history recording
  vim_api.nvim_set_option_value("undolevels", ul_orig, { scope = "local" })
end

---Push current line up to the chunk above, joining to the end of its counterpart
---@param a table
M.cmd.push_up = function(a)
  local here, lineno, lnum
  if a ~= nil and a.fargs ~= nil then lnum = tonumber(a.fargs[1]) end

  if lnum == nil then
    here = vim_api.nvim_win_get_cursor(0)
    lineno = here[1]
  else
    lineno = lnum
    here = { lineno, 1 }
  end

  _H.push_up(lineno, here, true)
end

---Pull the counterpart line from the chunk below up to the end of current line
---@param a table
M.cmd.pull_below = function(a)
  local here, lineno, lnum
  if a ~= nil and a.fargs ~= nil then lnum = tonumber(a.fargs[1]) end

  if lnum == nil then
    here = vim_api.nvim_win_get_cursor(0)
    lineno = here[1]
  else
    lineno = lnum
    here = { lineno, 1 }
  end
  if store == nil then store = true end

  _H.push_up(lineno + (M.config.lang_num + 1), here, true)
end

---Helper for PushUpPair and PullBelowPair
---@param lnum integer
---@param here integer[]
---@param store boolean|nil
_H.push_up_pair = function(lnum, here, store)
  if lnum < (M.config.lang_num + 1) or lnum % (M.config.lang_num + 1) == 0 then return end
  if store == nil then store = true end

  -- temporarily disable undo history recording
  local ul_orig = vim_api.nvim_get_option_value("undolevels", { scope = "local" })
  vim_api.nvim_set_option_value("undolevels", -1, { scope = "local" })

  -- locate first chunk line
  local lineno = lnum - lnum % (M.config.lang_num + 1)

  local cnums = {}
  for offset = 1, M.config.lang_num do table.insert(cnums, _H.append_to_3_lines_above(lineno + offset)) end

  lineno = lineno + (M.config.lang_num + 1)
  local last_lineno = vim_api.nvim_buf_line_count(0)

  local soft_last_lineno = math.min(last_lineno, lineno + 200 * (M.config.lang_num + 1))
  while lineno <= soft_last_lineno do
    for offset = 1, M.config.lang_num do
      setline((lineno + offset) - (M.config.lang_num + 1), getline(lineno + offset))
    end
    lineno = lineno + (M.config.lang_num + 1)
  end

  vim_api.nvim_win_set_cursor(0, here)
  if vim_api.nvim__redraw ~= nil then
    vim_api.nvim__redraw({ win = 0, flush = true })
    -- fix the screen is not updated to respect `scrolloff` when cursor is at
    -- bottom joining a line from below that occupies multiple screen-lines.
    vim_cmd "normal! jk"
    vim_api.nvim__redraw({ win = 0, cursor = true, flush = true })
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

  _H.delete_trailing_empty_lines()

  if store then
    _H.store_undo {
      function() _H.push_up_pair(lnum, here, false) end,
      function() _H.downward_pair(lnum - (M.config.lang_num + 1), cnums, false) end,
    }
    M._redos = {}
  end

  -- enable undo history recording
  vim_api.nvim_set_option_value("undolevels", ul_orig, { scope = "local" })
end

---@param lnum integer
---@param cnums integer[]
---@param store boolean|nil
_H.downward_pair = function(lnum, cnums, store)
  local curr_chunk_prev_lineno = lnum - lnum % (M.config.lang_num + 1)
  if store == nil then store = true end

  -- temporarily disable undo history recording
  local ul_orig = vim_api.nvim_get_option_value("undolevels", { scope = "local" })
  vim_api.nvim_set_option_value("undolevels", -1, { scope = "local" })

  local last_lineno = vim_api.nvim_buf_line_count(0)
  for _ = 1, M.config.lang_num + 1 do vim_fn.append(last_lineno, "") end

  local last_chunk_prev_lineno = last_lineno - last_lineno % (M.config.lang_num + 1)
  local next_chunk_prev_lineno = curr_chunk_prev_lineno + (M.config.lang_num + 1)
  local soft_last_chunk_prev_lineno = math.min(last_chunk_prev_lineno,
    next_chunk_prev_lineno + 200 * (M.config.lang_num + 1))
  local lineno = soft_last_chunk_prev_lineno - (M.config.lang_num + 1)
  local cache_lines = vim_api.nvim_buf_get_lines(0, soft_last_chunk_prev_lineno,
    soft_last_chunk_prev_lineno + (M.config.lang_num + 1), false)

  while lineno >= next_chunk_prev_lineno do
    for offset = 1, M.config.lang_num do
      setline((lineno + offset) + (M.config.lang_num + 1), getline(lineno + offset))
    end
    lineno = lineno - (M.config.lang_num + 1)
  end -- lineno == curr_chunk_prev_lineno after the while loop
  for offset = 1, M.config.lang_num do
    local line = getline(curr_chunk_prev_lineno + offset)
    setline(curr_chunk_prev_lineno + offset, (line:sub(1, cnums[offset] - 1):gsub("%s+$", "")))
    setline(next_chunk_prev_lineno + offset, (line:sub(cnums[offset]):gsub("^%s+", "")))
  end

  if vim_api.nvim__redraw ~= nil then
    vim_api.nvim__redraw({ win = 0, cursor = true, flush = true })
  end

  lineno = last_chunk_prev_lineno
  while lineno > soft_last_chunk_prev_lineno do
    for offset = 1, M.config.lang_num do
      setline((lineno + offset) + (M.config.lang_num + 1), getline(lineno + offset))
    end
    lineno = lineno - (M.config.lang_num + 1)
  end
  for offset = 1, M.config.lang_num do
    setline((soft_last_chunk_prev_lineno + offset) + (M.config.lang_num + 1),
      cache_lines[offset])
  end

  _H.delete_trailing_empty_lines()

  if store then
    _H.store_undo {
      function() _H.downward_pair(lnum, cnums, false) end,
      function() _H.push_up(lnum + (M.config.lang_num + 1), { lnum + M.config.lang_num + 1, 1 }, false) end,
    }
    M._redos = {}
  end

  -- enable undo history recording
  vim_api.nvim_set_option_value("undolevels", ul_orig, { scope = "local" })
end

---Push current chunk up to the one above, joining each line to the end of the corresponding counterpart
---@param a table
M.cmd.push_up_pair = function(a)
  local here = vim_api.nvim_win_get_cursor(0)

  local lineno
  if a ~= nil and a.fargs ~= nil then lineno = tonumber(a.fargs[1]) end
  if lineno == nil then lineno = here[1] end

  if lineno <= (M.config.lang_num + 1) or lineno % (M.config.lang_num + 1) == 0 then return end

  _H.push_up_pair(lineno, here, true)
end

---Pull the chunk below up to current chunk, joining each line to the end of the corresponding line
---@param a table
M.cmd.pull_below_pair = function(a)
  local here = vim_api.nvim_win_get_cursor(0)

  local lineno
  if a ~= nil and a.fargs ~= nil then lineno = tonumber(a.fargs[1]) end
  if lineno == nil then lineno = here[1] end
  if vim_api.nvim_buf_line_count(0) - lineno <= (M.config.lang_num) then return end

  _H.push_up_pair(lineno + (M.config.lang_num + 1), here, true)
end

---@param a table
M.cmd.push_down_right_part = function(a)
  local lnum, cnum
  if a ~= nil and a.fargs ~= nil then
    lnum = tonumber(a.fargs[1])
    cnum = tonumber(a.fargs[2])
  end
  _H.push_down_right_part(lnum, cnum, true)
end

---Push the text on the right side of the cursor in the current line down to the chunk below
---@param lnum integer|nil
---@param cnum integer|nil
---@param store boolean|nil
_H.push_down_right_part = function(lnum, cnum, store)
  local curr_lineno = lnum or vim_fn.line(".")
  local languid = curr_lineno % (M.config.lang_num + 1)
  if languid == 0 then return end
  local curr_colno = cnum or vim_fn.col(".")
  if store == nil then store = true end

  -- temporarily disable undo history recording
  local ul_orig = vim_api.nvim_get_option_value("undolevels", { scope = "local" })
  vim_api.nvim_set_option_value("undolevels", -1, { scope = "local" })

  local last_lineno = vim_api.nvim_buf_line_count(0)
  for _ = 1, M.config.lang_num + 1 do vim_fn.append(last_lineno, "") end
  local last_counterpart_lineno = last_lineno - (last_lineno - curr_lineno) % (M.config.lang_num + 1)
  local soft_last_counterpart_lineno = math.min(last_counterpart_lineno, curr_lineno + 200 * (M.config.lang_num + 1))
  local lineno = soft_last_counterpart_lineno - (M.config.lang_num + 1)
  local cache_line = getline(soft_last_counterpart_lineno)

  while lineno > curr_lineno do
    setline(lineno + (M.config.lang_num + 1), getline(lineno))
    lineno = lineno - (M.config.lang_num + 1)
  end

  local curr_line = getline(curr_lineno)
  local before_cursor = curr_line:sub(1, curr_colno - 1)
  local after_cursor = curr_line:sub(curr_colno)
  before_cursor = before_cursor:gsub([[%s+$]], "", 1)
  after_cursor = after_cursor:gsub([[^%s+]], "", 1)
  local sep = M.config.language_separator[tostring(languid)] or ""
  before_cursor = vim_fn.substitute(before_cursor, ("%s$"):format(vim_fn.escape(sep, [[\]])), "", "")
  after_cursor = vim_fn.substitute(after_cursor, ("^%s"):format(vim_fn.escape(sep, [[\]])), "", "")
  local cntrprt_lineno = curr_lineno + (M.config.lang_num + 1)
  setline(curr_lineno, before_cursor)
  setline(cntrprt_lineno, after_cursor)

  if vim_api.nvim__redraw ~= nil then
    vim_api.nvim__redraw({ win = 0, cursor = true, flush = true })
  end

  if curr_lineno ~= last_counterpart_lineno then
    lineno = last_counterpart_lineno
    while lineno > soft_last_counterpart_lineno do
      setline(lineno + (M.config.lang_num + 1), getline(lineno))
      lineno = lineno - (M.config.lang_num + 1)
    end
    setline(soft_last_counterpart_lineno + (M.config.lang_num + 1), cache_line)
  end

  _H.delete_trailing_empty_lines()
  if store then
    _H.store_undo {
      function() _H.push_down_right_part(curr_lineno, curr_colno, false) end,
      function() _H.push_up(cntrprt_lineno, { curr_lineno, 1 }, false) end,
    }
    M._redos = {}
  end

  -- enable undo history recording
  vim_api.nvim_set_option_value("undolevels", ul_orig, { scope = "local" })
end

---@param a table
M.cmd.push_up_left_part = function(a)
  local lnum, cnum
  if a ~= nil and a.fargs ~= nil then
    lnum = tonumber(a.fargs[1])
    cnum = tonumber(a.fargs[2])
  end
  _H.push_up_left_part(lnum, cnum, true)
end

---Push the text on the left side of the cursor in the current line up to the chunk above, appending to the end of its couunterpart
_H.push_up_left_part = function(lnum, cnum, store)
  local curr_lineno = lnum or vim_fn.line(".")
  local languid = curr_lineno % (M.config.lang_num + 1)
  if languid == 0 or curr_lineno <= M.config.lang_num then return end
  local curr_colno = cnum or vim_fn.col(".")
  if store == nil then store = true end

  -- temporarily disable undo history recording
  local ul_orig = vim_api.nvim_get_option_value("undolevels", { scope = "local" })
  vim_api.nvim_set_option_value("undolevels", -1, { scope = "local" })

  -- get left and right parts of curr_lineno
  local curr_line = getline(curr_lineno)
  local before_cursor = curr_line:sub(1, curr_colno - 1)
  local after_cursor = curr_line:sub(curr_colno)
  before_cursor = before_cursor:gsub([[%s+$]], "", 1)
  after_cursor = after_cursor:gsub([[^%s+]], "", 1)
  local sep = M.config.language_separator[tostring(languid)] or ""
  before_cursor = vim_fn.substitute(before_cursor, ("%s$"):format(vim_fn.escape(sep, [[\]])), "", "")
  after_cursor = vim_fn.substitute(after_cursor, ("^%s"):format(vim_fn.escape(sep, [[\]])), "", "")

  local cntrprt_lineno = curr_lineno - (M.config.lang_num + 1)
  local cntrprt_line = getline(cntrprt_lineno)
  setline(cntrprt_lineno, ("%s%s%s"):format(cntrprt_line, sep, before_cursor))
  setline(curr_lineno, after_cursor)

  vim_fn.cursor(curr_lineno, 1)

  if store then
    _H.store_undo {
      function() _H.push_up_left_part(curr_lineno, curr_colno, false) end,
      function() _H.push_down_right_part_join(cntrprt_lineno, #cntrprt_line + #sep + 1, false) end,
    }
    M._redos = {}
  end

  -- enable undo history recording
  vim_api.nvim_set_option_value("undolevels", ul_orig, { scope = "local" })
end

_H.push_down_right_part_join = function(lnum, cnum, store)
  local curr_lineno = lnum or vim_fn.line(".")
  local languid = curr_lineno % (M.config.lang_num + 1)
  if languid == 0 or vim_fn.line('$') - curr_lineno < M.config.lang_num then return end
  local curr_colno = cnum or vim_fn.col(".")
  if store == nil then store = true end

  -- temporarily disable undo history recording
  local ul_orig = vim_api.nvim_get_option_value("undolevels", { scope = "local" })
  vim_api.nvim_set_option_value("undolevels", -1, { scope = "local" })

  local curr_line = getline(curr_lineno)
  local before_cursor = curr_line:sub(1, curr_colno - 1)
  local after_cursor = curr_line:sub(curr_colno)
  before_cursor = before_cursor:gsub([[%s+$]], "", 1)
  after_cursor = after_cursor:gsub([[^%s+]], "", 1)
  local sep = M.config.language_separator[tostring(languid)] or ""
  before_cursor = vim_fn.substitute(before_cursor, ("%s$"):format(vim_fn.escape(sep, [[\]])), "", "")
  after_cursor = vim_fn.substitute(after_cursor, ("^%s"):format(vim_fn.escape(sep, [[\]])), "", "")


  local cntrprt_lineno = curr_lineno + (M.config.lang_num + 1)
  local cntrprt_line = getline(cntrprt_lineno)
  setline(curr_lineno, before_cursor)
  setline(cntrprt_lineno, ("%s%s%s"):format(after_cursor, sep, cntrprt_line))

  if store then
    _H.store_undo {
      function() _H.push_down_right_part_join(curr_lineno, curr_colno, false) end,
      function() _H.push_up_left_part(cntrprt_lineno, #after_cursor + #sep + 1, false) end,
    }
    M._redos = {}
  end

  -- enable undo history recording
  vim_api.nvim_set_option_value("undolevels", ul_orig, { scope = "local" })
end

---Push current line down to the chunk below
---@param a table
M.cmd.push_down = function(a)
  local lnum
  if a ~= nil and a.fargs ~= nil then
    lnum = tonumber(a.fargs[1])
  end
  _H.push_down_right_part(lnum, 1, true)
end

---@param a table
M.cmd.leave_alone = function(a)
  local lnum
  if a ~= nil and a.fargs ~= nil then
    lnum = tonumber(a.fargs[1])
  end
  _H.leave_alone(lnum, true)
end

---@param lnum integer|nil
---@param store boolean|nil
_H.leave_alone = function(lnum, store)
  local curr_lineno = lnum or vim_fn.line(".")
  local languid = curr_lineno % (M.config.lang_num + 1)
  if languid == 0 then return end
  if store == nil then store = true end

  -- temporarily disable undo history recording
  local ul_orig = vim_api.nvim_get_option_value("undolevels", { scope = "local" })
  vim_api.nvim_set_option_value("undolevels", -1, { scope = "local" })

  local last_lineno = vim_api.nvim_buf_line_count(0)
  for _ = 1, M.config.lang_num + 1 do vim_fn.append(last_lineno, "") end

  local last_chunk_prev_lineno = last_lineno - last_lineno % (M.config.lang_num + 1)
  local curr_chunk_prev_lineno = curr_lineno - languid
  local soft_last_chunk_prev_lineno = math.min(last_chunk_prev_lineno,
    curr_chunk_prev_lineno + 200 * (M.config.lang_num + 1))
  local lineno = soft_last_chunk_prev_lineno - (M.config.lang_num + 1)
  local cache_lines = vim_api.nvim_buf_get_lines(0, soft_last_chunk_prev_lineno,
    soft_last_chunk_prev_lineno + (M.config.lang_num + 1), false)

  while lineno >= curr_chunk_prev_lineno do
    for offset = 1, M.config.lang_num do
      if offset ~= languid then setline((lineno + offset) + (M.config.lang_num + 1), getline(lineno + offset)) end
    end
    lineno = lineno - (M.config.lang_num + 1)
  end
  for offset = 1, M.config.lang_num do
    if offset ~= languid then setline(curr_chunk_prev_lineno + offset, "-") end
  end

  M.cmd.navigate_down()
  if vim_api.nvim__redraw ~= nil then
    vim_api.nvim__redraw({ win = 0, cursor = true, flush = true })
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

  if store then
    _H.store_undo {
      function() _H.leave_alone(curr_lineno, false) end,
      function() _H.put_together(curr_lineno, false) end,
    }
    M._redos = {}
  end

  -- enable undo history recording
  vim_api.nvim_set_option_value("undolevels", ul_orig, { scope = "local" })
end

---Inverse of LeaveAlone
---@param lnum integer
---@param store boolean|nil
_H.put_together = function(lnum, store)
  local curr_lineno = lnum or vim_fn.line(".")
  local languid = curr_lineno % (M.config.lang_num + 1)
  if languid == 0 then return end
  local curr_chunk_prev_lineno = curr_lineno - languid
  if store == nil then store = true end

  -- temporarily disable undo history recording
  local ul_orig = vim_api.nvim_get_option_value("undolevels", { scope = "local" })
  vim_api.nvim_set_option_value("undolevels", -1, { scope = "local" })

  local lineno = curr_chunk_prev_lineno + (M.config.lang_num + 1)
  local last_lineno = vim_api.nvim_buf_line_count(0)
  local soft_last_lineno = math.min(last_lineno, lineno + 200 * (M.config.lang_num + 1))

  while lineno <= soft_last_lineno do
    for offset = 1, M.config.lang_num do
      if offset ~= languid then setline((lineno + offset) - (M.config.lang_num + 1), getline(lineno + offset)) end
    end
    lineno = lineno + (M.config.lang_num + 1)
  end

  if vim_api.nvim__redraw ~= nil then
    vim_api.nvim__redraw({ win = 0, flush = true })
    -- fix the screen is not updated to respect `scrolloff` when cursor is at
    -- bottom joining a line from below that occupies multiple screen-lines.
    vim_cmd "normal! jk"
    vim_api.nvim__redraw({ win = 0, cursor = true, flush = true })
  end

  while lineno <= last_lineno do
    for offset = 1, M.config.lang_num do
      if offset ~= languid then setline((lineno + offset) - (M.config.lang_num + 1), getline(lineno + offset)) end
    end
    lineno = lineno + (M.config.lang_num + 1)
  end
  for offset = 1, M.config.lang_num do
    setline((lineno + offset) - (M.config.lang_num + 1), "")
  end

  _H.delete_trailing_empty_lines()

  if store then
    _H.store_undo {
      function() _H.put_together(curr_lineno, false) end,
      function() _H.leave_alone(curr_lineno, false) end,
    }
    M._redos = {}
  end

  -- enable undo history recording
  vim_api.nvim_set_option_value("undolevels", ul_orig, { scope = "local" })
end

---@param a table
M.cmd.swap_with_above = function(a)
  local lnum
  if a ~= nil and a.fargs ~= nil then
    lnum = tonumber(a.fargs[1])
  end
  _H.swap_with_above(lnum, true)
end

---@param lnum integer|nil
---@param store boolean|nil
_H.swap_with_above = function(lnum, store)
  local curr_lineno = lnum or vim_fn.line(".")
  if curr_lineno % (M.config.lang_num + 1) == 0 or curr_lineno <= M.config.lang_num then return end
  if store == nil then store = true end

  -- temporarily disable undo history recording
  local ul_orig = vim_api.nvim_get_option_value("undolevels", { scope = "local" })
  vim_api.nvim_set_option_value("undolevels", -1, { scope = "local" })

  local cntrprt_lineno = curr_lineno - (M.config.lang_num + 1)
  local cntrprt_line = getline(cntrprt_lineno)
  setline(cntrprt_lineno, getline(curr_lineno))
  setline(curr_lineno, cntrprt_line)

  vim_fn.cursor(cntrprt_lineno, 1)

  if store then
    _H.store_undo {
      function() _H.swap_with_above(curr_lineno, false) end,
      function() _H.swap_with_above(curr_lineno, false) end,
    }
  end

  -- enable undo history recording
  vim_api.nvim_set_option_value("undolevels", ul_orig, { scope = "local" })
end

---@param a table
M.cmd.swap_with_below = function(a)
  local lnum
  if a ~= nil and a.fargs ~= nil then
    lnum = tonumber(a.fargs[1])
  end
  _H.swap_with_below(lnum, true)
end

---@param lnum integer|nil
---@param store boolean|nil
_H.swap_with_below = function(lnum, store)
  local curr_lineno = lnum or vim_fn.line(".")
  if curr_lineno % (M.config.lang_num + 1) == 0 or vim_api.nvim_buf_line_count(0) - curr_lineno + 1 <= M.config.lang_num then return end
  if store == nil then store = true end

  -- temporarily disable undo history recording
  local ul_orig = vim_api.nvim_get_option_value("undolevels", { scope = "local" })
  vim_api.nvim_set_option_value("undolevels", -1, { scope = "local" })

  local cntrprt_lineno = curr_lineno + (M.config.lang_num + 1)
  local cntrprt_line = getline(cntrprt_lineno)
  setline(cntrprt_lineno, getline(curr_lineno))
  setline(curr_lineno, cntrprt_line)

  vim_fn.cursor(cntrprt_lineno, 1)

  if store then
    _H.store_undo {
      function() _H.swap_with_below(curr_lineno, false) end,
      function() _H.swap_with_below(curr_lineno, false) end,
    }
  end

  -- enable undo history recording
  vim_api.nvim_set_option_value("undolevels", ul_orig, { scope = "local" })
end

--------------------------------RE-POSITION END---------------------------------

---@param t function[] the first func is for redo, second undo
_H.store_undo = function(t)
  if #M._undos >= 100 then table.remove(M._undos, 1) end
  table.insert(M._undos, t)
end

---@param t function[] the first func is for redo, second undo
_H.store_redo = function(t)
  -- don't have to limit _redos length because it will have at most the same length of _undos
  -- any reposition during the redoing will clear the _redos
  table.insert(M._redos, t)
end

M.cmd.undo = function(a)
  local c, t
  if a == nil then
    --called from keymapping
    --reference: https://www.reddit.com/r/vim/comments/bj0fip/comment/em4i23z/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
    c = vim.v.count1
  else
    --called from command-line
    c = a.count ~= nil and a.count or 1
  end
  for _ = 1, c do
    t = table.remove(M._undos)
    if t ~= nil then
      t[2]()
      _H.store_redo(t)
    else
      logger.info("Already at oldest change")
    end
  end
end

M.cmd.redo = function(a)
  local c, t
  if a == nil then
    --called from keymapping
    --reference: https://www.reddit.com/r/vim/comments/bj0fip/comment/em4i23z/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
    c = vim.v.count1
  else
    --called from command-line
    c = a.count ~= nil and a.count or 1
  end
  for _ = 1, c do
    t = table.remove(M._redos)
    if t ~= nil then
      t[1]()
      _H.store_undo(t)
    else
      logger.info("Already at newest change")
    end
  end
end

---Move cursor to the chunk below at the counterpart of current line
M.cmd.navigate_down = function(a)
  local c
  if a == nil then
    --called from keymapping
    --reference: https://www.reddit.com/r/vim/comments/bj0fip/comment/em4i23z/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
    c = vim.v.count1
  else
    --called from command-line
    c = a.count ~= nil and a.count or 1
  end
  vim_cmd(("normal! 0%sj"):format(c * (M.config.lang_num + 1)))
end

---Move cursor to the chunk above at the counterpart of current line
M.cmd.navigate_up = function(a)
  local c
  if a == nil then
    --called from keymapping
    --reference: https://www.reddit.com/r/vim/comments/bj0fip/comment/em4i23z/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
    c = vim.v.count1
  else
    --called from command-line
    c = a.count ~= nil and a.count or 1
  end
  vim_cmd(("normal! 0%sk"):format(c * (M.config.lang_num + 1)))
end

---:[range]ItDeInterlace [num], works on the whole buffer if range is not provided
---upper- and lower-most empty lines are ignored
---requires the range is paired, [(, L2_1), (L1_2, L2_2), (L1_3, L2_3), ...] will make the buffer chaotic
---@param a table
M.cmd.deinterlace = function(a)
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
  local lines = vim_api.nvim_buf_get_lines(0, a.line1 - 1, a.line2, false)
  local sents = {}
  for _, line in ipairs(lines) do
    vim.list_extend(sents, vim_fn.split(line, regex))
  end
  vim_api.nvim_buf_set_lines(0, 0, -1, false, sents)
end

---Insert a newline at end of each Chinese sentence boundaries
---@param a table
---@return nil
M.cmd.split_chinese_sentences = function(a)
  -- :h split()
  -- Use '\zs' at the end of the pattern to keep the separator.
  -- :echo split('bar:foo', ':\zs')
  local regex = [[\v[…。｡．!！?？]+[”"’'）)】」﹂』》］｝〕〗〙〛〉]*\zs]]
  _H.SplitHelper(regex, a)
end

---Insert a newline at end of each English sentence boundaries
---@param a table
---@return nil
M.cmd.split_english_sentences = function(a)
  local regex = [[\v%(%(%(<al)@<!%(\u\l{,2})@<!(\.\a)@<!\.|[!?])+['’"”]?)\zs%(\s+|$)]]
  _H.SplitHelper(regex, a)
end

---:[range]ItInterlace [lang_num]
---Works on the whole buffer when range is not provided. Uses config.lang_num when lang_num is not provided.
---Empty lines are filtered out before the interlacement.
---@param a table
---@return nil
M.cmd.interlace = function(a)
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
  local lastline = direction == 1 and vim_api.nvim_buf_line_count(0) or 1

  local chunk_lines
  local group_count1, group_count2
  for l = lineno, lastline, direction * (M.config.lang_num + 1) do
    chunk_lines = vim_api.nvim_buf_get_lines(buf, l - 1, l - 1 + M.config.lang_num, false)
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
          logger.info(("Jumped over %s lines"):format(math.abs(l - lineno_orig)))
          return
        end
        for k1, _ in pairs(group_count1) do
          if group_count2[k1] == nil then
            vim_api.nvim_win_set_cursor(0, { l, 1 })
            vim_cmd "normal! zz"
            logger.info(("Jumped over %s lines"):format(math.abs(l - lineno_orig)))
            return
          end
        end
      end
    end
  end

  vim.print("Not Found")
end

M.cmd.next_unaligned = function() _H.locate_unaligned(1) end
M.cmd.prev_unaligned = function() _H.locate_unaligned(-1) end

return M
