#!/usr/bin/env lua

local keyset = vim.keymap.set
local vim_fn = vim.fn
local vim_api = vim.api
local vim_cmd = vim.cmd
local vim_uv = vim.uv or vim.loop

local defaults = require("interlaced.config")
local mt = require("interlaced.match")
local rpst = require("interlaced.reposition")
local utils = require("interlaced.utils")
local logger = require("interlaced.logger")
local _io = require("interlaced._io")
local _str = require("interlaced._str")

local _H = {}
local M = {
  _H = _H,
  _orig_mappings = {},
  _is_mappings_on = false,
  _ns_id = nil,
  -- A list of regex patterns (named entities, numbers, dates, etc) users want to highlight
  -- :h matchadd()
  -- Matching is case sensitive and magic, unless case sensitivity
  -- or magicness are explicitly overridden in {pattern}.  The
  config = {},
  cmd = {},
}

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
  return ("%s.%s"):format(timestr, stamp)
end


---@param params table
---@param is_curbuf_l1 boolean
---@return nil
_H.InterlaceWithL = function(params, is_curbuf_l1)
  local filepath = params.args
  local fh, err = io.open(filepath, "r")
  if not fh then
    logger.warning(("Failed to open file for reading: %s\nError: %s"):format(filepath, err))
    return
  end
  local lines_that = {}
  for line in fh:lines() do
    table.insert(lines_that, line)
  end
  fh:close()
  local lines_this = vim_api.nvim_buf_get_lines(0, 0, -1, true)
  lines_this = vim.tbl_filter(function(s) return s:find("%S") ~= nil end, lines_this)
  lines_that = vim.tbl_filter(function(s) return s:find("%S") ~= nil end, lines_that)
  local lines = is_curbuf_l1 and _H.zip(lines_this, lines_that) or _H.zip(lines_that, lines_this)
  local time = _H.get_timestr()
  local interlaced_path = ("%s.interlaced.txt"):format(time)
  vim_fn.writefile(lines, interlaced_path)
  vim_cmd(("edit %s"):format(interlaced_path))
  if not M._is_mappings_on then
    M.cmd.enable_keybindings()
  end
end

---@param params table
---@return nil
M.cmd.interlace_with_l1 = function(params)
  _H.InterlaceWithL(params, false)
end

---@param params table
---@return nil
M.cmd.interlace_with_l2 = function(params)
  _H.InterlaceWithL(params, true)
end

---Interlace current buffer with files, placing current buffer at position {n}
---@param a table
---@return nil
M.cmd.interlace_as_l = function(a)
  if #a.fargs < 2 then
    logger.error("Usage: ItInterlaceAsL {n} {filepath} [filepath ...]")
    return
  end

  local n = tonumber(a.fargs[1])
  if n == nil or n < 1 then
    logger.error("First argument must be a positive integer")
    return
  end

  table.remove(a.fargs, 1)

  -- Read current buffer content
  local current_lines = vim_api.nvim_buf_get_lines(0, 0, -1, true)
  current_lines = vim.tbl_filter(function(s) return s:find("%S") ~= nil end, current_lines)

  -- Read file contents
  local file_contents = {}
  for _, filepath in ipairs(a.fargs) do
    local fh, err = io.open(filepath, "r")
    if not fh then
      logger.warning(("Failed to open file for reading: %s\nError: %s"):format(filepath, err))
      return
    end
    local lines = {}
    for line in fh:lines() do
      table.insert(lines, line)
    end
    fh:close()
    table.insert(file_contents, lines)
  end

  -- Determine the number of languages
  local lang_num = #file_contents + 1

  -- Ensure n is within valid range
  if n > lang_num then
    logger.error(("n cannot be greater than the number of languages (%s)"):format(lang_num))
    return
  end

  -- Interlace the lines
  local interlaced_lines = {}
  local max_lines = #current_lines
  for i = 1, #file_contents do
    max_lines = math.max(max_lines, #file_contents[i])
  end

  for i = 1, max_lines do
    for lang = 1, lang_num do
      if lang == n then
        table.insert(interlaced_lines, current_lines[i] or "")
      else
        local file_idx = lang < n and lang or lang - 1
        table.insert(interlaced_lines, file_contents[file_idx][i] or "")
      end
    end
    table.insert(interlaced_lines, "") -- Add an empty line between chunks
  end

  -- Create a new buffer with the interlaced content
  local time = _H.get_timestr()
  local interlaced_path = ("%s.interlaced.txt"):format(time)
  vim_fn.writefile(interlaced_lines, interlaced_path)
  vim_cmd(("edit %s"):format(interlaced_path))

  M.config.lang_num = 1 + #a.fargs
  -- Enable keybindings if not already enabled
  if not M._is_mappings_on then
    M.cmd.enable_keybindings()
  end
end

---Enable custom keybindings as defined in M.config.mappings.
M.cmd.enable_keybindings = function()
  if type(M.config.enable_keybindings_hook) == "function" then M.config.enable_keybindings_hook() end
  if M._is_mappings_on then
    logger.warning("Keybindings already on, nothing to do")
    return
  end
  if M.config.keymaps == nil then return end
  local mode, lhs, rhs, opts
  for _, entry in ipairs(M.config.keymaps) do
    mode, lhs, rhs, opts = unpack(entry)
    _H.store_orig_mapping(lhs, mode)
    keyset(mode, lhs, rhs, opts)
  end
  logger.info("Keybindings on")
  M._is_mappings_on = true
end

---Disable all keybindings set by EnableKeybindings.
M.cmd.disable_keybindings = function()
  if type(M.config.disable_keybindings_hook) == "function" then M.config.disable_keybindings_hook() end
  if not M._is_mappings_on then
    logger.warning("Keybindings already off, nothing to do")
    return
  end
  if M.config.keymaps ~= nil then
    local mode, lhs, _
    for _, entry in ipairs(M.config.keymaps) do
      mode, lhs, _, _ = unpack(entry)
      pcall(vim_api.nvim_buf_del_keymap, 0, mode, lhs)
    end
  end
  for _, mapargs in ipairs(M._orig_mappings) do
    if next(mapargs) ~= nil then
      mapargs.buffer = true
      vim_fn.mapset(mapargs)
    end
  end
  logger.info("Keybindings off")
  M._is_mappings_on = false
  M._orig_mappings = {}
end

M.ShowChunkNr = function()
  if M._showing_chunknr == true then return end
  if M._ns_id == nil then M._ns_id = vim_api.nvim_create_namespace("interlaced") end

  local last_lineno = vim_fn.line("$")
  local opts = { right_gravity = true, virt_text_win_col = 0, hl_mode = "combine" }
  local chunkno = 1
  -- nvim_buf_set_extmark uses 0-based, end-exclusive index, thus - 1
  for lineno = 0, last_lineno - 2 * M.config.lang_num, M.config.lang_num + 1 do
    opts.virt_text = { { string.format("%s ", chunkno), "LineNr" } }
    vim_api.nvim_buf_set_extmark(0, M._ns_id, lineno + M.config.lang_num, 0, opts)
    chunkno = chunkno + 1
  end

  M._showing_chunknr = true
end

M.ClearChunkNr = function()
  if M._ns_id == nil then return end

  for _, m in ipairs(vim_api.nvim_buf_get_extmarks(0, M._ns_id, 0, -1, {})) do
    vim_api.nvim_buf_del_extmark(0, M._ns_id, m[1])
  end
  M._showing_chunknr = false
end

M.cmd.toggle_chunk_number = function()
  if M._showing_chunknr == nil then M._showing_chunknr = false end

  if M._showing_chunknr then
    M.ClearChunkNr()
  else
    M.ShowChunkNr()
  end
end

M.cmd.set_separator = function(a)
  -- :ItSetSeparator ?
  -- :ItSetSeparator
  if #a.fargs == 0 or a.args == "?" then
    for _, l in ipairs(vim_fn.sort(vim.tbl_keys(M.config.language_separator))) do
      vim.print(("L%s: '%s'"):format(l, M.config.language_separator[l]))
    end
    return
  end

  -- :ItSetSeparator {int} {str}
  if #a.fargs ~= 2 then
    logger.error(("Expected 2 arguments, got %s"):format(#a.fargs))
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
  vim.print(("L%s separator: '%s'"):format(l, sep))
end

---@param n nil|string|number
M.cmd.set_lang_num = function(n)
  -- :ItSetLangNum ?
  -- :ItSetLangNum
  if n == nil or n == "?" then
    vim.print(("Language number: %s"):format(M.config.lang_num))
    return
  end

  -- :ItSetLangNum {int}
  n = tonumber(n)
  M.config.lang_num = n
  rpst.config.lang_num = n

  -- default separator when language number grows
  while #M.config.language_separator < n do
    table.insert(M.config.language_separator, " ")
  end

  M.ClearChunkNr()
  M.ShowChunkNr()

  vim.print(("Language number: %s"):format(M.config.lang_num))
end

M.cmd.dump = function(path)
  if path == nil then
    path = vim.fs.joinpath(vim_fn.expand("%:h"), ".interlaced.json")
  end
  local data = {
    curpos = vim_api.nvim_win_get_cursor(0),
    matches = vim_fn.getmatches(),
    config = {
      language_separator = M.config.language_separator,
      lang_num = M.config.lang_num
    },
  }

  if not _io.write(path, vim.json.encode(data)) then return end
  logger.info(("dumpped at %s"):format(os.date("%H:%M:%S")))
end

M.cmd.load = function(a)
  local path
  if a == nil or a.args == nil or #a.args == 0 then
    path = vim.fs.joinpath(vim_fn.expand("%:h"), ".interlaced.json")
  else
    path = a.args
  end

  local data = _io.read(path)
  if data == nil then return end

  ok, ret = pcall(vim.json.decode, data)
  if not ok then return end

  if ret.curpos ~= nil then
    vim_api.nvim_win_set_cursor(0, ret.curpos)
  end
  if ret.matches ~= nil then
    vim_fn.setmatches(ret.matches)
    mt._matches = utils.match_list2dict(ret.matches)
  end
  if ret.config ~= nil then
    M.config = vim.tbl_deep_extend("force", M.config, ret.config)
    rpst.config = vim.tbl_deep_extend("force", rpst.config, ret.config)
  end
end

---@param key string
---@param mode string|string[]
---@return nil
_H.store_orig_mapping = function(key, mode)
  if type(mode) == "string" then
    table.insert(M._orig_mappings, vim_fn.maparg(key, mode, false, true))
  else
    for _, m in ipairs(mode) do
      table.insert(M._orig_mappings, vim_fn.maparg(key, m, false, true))
    end
  end
end

---User passed opts are lost.
M.cmd.reload = function()
  local pkg_name = "interlaced"
  require(pkg_name)._showing_chunknr = true
  require(pkg_name).cmd.toggle_chunk_number()
  for k, _ in pairs(package.loaded) do
    if k:sub(1, #pkg_name) == pkg_name then
      package.loaded[k] = nil
    end
  end
  require(pkg_name).setup({})
  vim.print(("%s restarted at %s"):format(pkg_name, os.date("%H:%M:%S")))
end

vim_api.nvim_create_user_command("Interlaced", function(a)
  ---@type string[]
  for _, provider in ipairs({ rpst, mt, M }) do
    cmd = provider.cmd[a.fargs[1]]
    if cmd ~= nil then break end
  end
  if cmd ~= nil then
    a.args = vim.trim(_str.removeprefix(a.args, a.fargs[1]))
    table.remove(a.fargs, 1)
    return cmd(a)
  else
    logger.error(string.format("%s not found", a.args))
  end
end, {
  complete = function(_, line)
    local candidates = vim.iter({ rpst.cmd, mt.cmd, M.cmd }):map(vim.tbl_keys):flatten():totable()
    table.sort(candidates)
    local args = vim.split(vim.trim(line), "%s+")
    if vim.tbl_count(args) > 2 then return end
    table.remove(args, 1)
    ---@type string
    local prefix = table.remove(args, 1)
    if prefix and line:sub(-1) == " " then return end
    if not prefix then
      return candidates
    else
      return vim.fn.matchfuzzy(candidates, prefix)
    end
  end,
  nargs = "*",
  range = "%"
})


------------------------------------- init -------------------------------------

global_opts = vim.g.interlaced or {}
M.config = vim.tbl_deep_extend("force", defaults, global_opts)
rpst.config = M.config

return M
