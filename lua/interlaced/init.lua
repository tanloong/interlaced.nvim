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
local _H = {}
local M = {
  _H = _H,
  _Name = "Interlaced",
  _orig_mappings = {},
  _is_mappings_set = false,
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
  for func, shortcut in pairs(M.config.mappings) do
    _H.store_orig_mapping(shortcut)
    keyset("n", shortcut, M.cmd[func], { noremap = true, buffer = true, nowait = true })
  end
  M.info("Keybindings have been enabled.")
  M._is_mappings_set = true
end

M.cmd.UnmapInterlaced = function()
  for keystroke, mapping in pairs(M._orig_mappings) do
    if vim.tbl_isempty(mapping) then
      vim_api.nvim_buf_del_keymap(0, "n", keystroke)
    else
      mapping.buffer = true
      vim_fn.mapset("n", false, mapping)
    end
  end
  M.info("Keybindings have been disabled.")
  M._is_mappings_set = false
end

M.cmd.JoinUp = function()
  local lineno = vim_fn.line(".")
  if lineno <= 3 then
    M.warning("Joining too early, please move down your cursor.")
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
  vim_cmd("w")
end

M.cmd.JoinUpPair = function()
  local here = vim_fn.getpos(".")
  vim_cmd([[normal! {]])
  for _ = 1, 2 do
    vim_fn.setcursorcharpos({ vim_fn.line(".") + 1, 1 })
    M.cmd.JoinUp()
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
  M.cmd.JoinUp()
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
    M.cmd.JoinUp()
  end
  vim_fn.setpos(".", here)
end

M.cmd.SplitAtCursor = function()
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
  vim_cmd("w")
end

M.cmd.JoinDown = function()
  vim_cmd([[normal! 0]])
  M.cmd.SplitAtCursor()
end

M.cmd.NavigateDown = function()
  vim_cmd([[normal! 03j]])
end

M.cmd.NavigateUp = function()
  vim_cmd([[normal! 03k]])
end

-- @param lines1 table
-- @param lines2 table
-- @return table
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

-- @return string
_H.get_timestr = function()
  local timestr = os.date("%Y-%m-%d.%H-%M-%S")
  local stamp = tostring(math.floor(vim_uv.hrtime() / 1000000) % 1000)
  while #stamp < 3 do
    stamp = "0" .. stamp
  end
  return timestr .. "." .. stamp
end

-- @param params table
-- @param is_curbuf_L1 boolean
-- @return nil
_H.interlace = function(params, is_curbuf_L1)
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

-- @param params table
-- @return nil
M.cmd.InterlaceWithL1 = function(params)
  _H.interlace(params, false)
end

-- @param params table
-- @return nil
M.cmd.InterlaceWithL2 = function(params)
  _H.interlace(params, true)
end

M.cmd.Deinterlace = function()
  local lines = vim_api.nvim_buf_get_lines(0, 0, -1, true)
  local lines_l1, lines_l2 = {}, {}
  for i = 1, #lines, 3 do
    table.insert(lines_l1, lines[i])
    table.insert(lines_l2, lines[i + 1])
  end
  while lines_l1[#lines_l1] == "" do
    table.remove(lines_l1)
  end
  while lines_l2[#lines_l2] == "" do
    table.remove(lines_l2)
  end
  local timestr = _H.get_timestr()
  local filepath1, filepath2 = timestr .. ".l1.txt", timestr .. ".l2.txt"
  vim_fn.writefile(lines_l1, filepath1)
  vim_fn.writefile(lines_l2, filepath2)
  vim.cmd("belowright split" .. filepath1)
  vim.cmd("belowright vsplit" .. filepath2)
end

_H.SplitHelper = function(regex)
  -- cmd([[saveas! %.splitted]])
  local buf = vim_api.nvim_get_current_buf()
  local last_lineno = vim_fn.line("$")
  for i = last_lineno, 1, -1 do
    line = getline(i)
    local sents = vim_fn.split(line, regex)

    vim_fn.deletebufline(buf, i)
    vim_fn.append(i - 1, sents)
  end
  vim_cmd([[w]])
end

M.cmd.SplitChineseSentences = function()
  -- :h split()
  -- Use '\zs' at the end of the pattern to keep the separator.
  -- :echo split('bar:foo', ':\zs')
  local regex = [[\v[…。!！?？—]+[’”"]?\zs]]
  _H.SplitHelper(regex)
end

M.cmd.SplitEnglishSentences = function()
  local regex = [[\v(%(%(\u\l{,2})@<!(\.\a)@<!\.|[!?])+['’"”]?)%(\s|$)\zs]]
  _H.SplitHelper(regex)
end

-- @param shortcut string
-- @return nil
_H.store_orig_mapping = function(shortcut)
  mapping = vim_fn.maparg(shortcut, "n", false, true)
  M._orig_mappings[shortcut] = mapping
end

-- @param opts table
-- @return nil
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

  for cmd, func in pairs(M.cmd) do
    create_command(cmd, function(params) func(params) end, {
      nargs = cmd:find("L%d$") and 1 or 0,
      complete = cmd:find("L%d$") and "file" or nil,
    })
  end
end

return M
