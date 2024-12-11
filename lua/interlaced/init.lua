#!/usr/bin/env lua

local keyset = vim.keymap.set
local vim_fn = vim.fn
local vim_api = vim.api
local vim_cmd = vim.cmd
local vim_uv = vim.uv or vim.loop
local create_command = vim_api.nvim_create_user_command

local config = require("interlaced.config")
local mt = require("interlaced.match")
local rpst = require("interlaced.reposition")
local utils = require("interlaced.utils")
local logger = require("interlaced.logger")

-- NOTE: Develop test mode !!
require("interlaced.test")

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

---Enable custom keybindings as defined in M.config.mappings.
M.cmd.EnableKeybindings = function()
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
M.cmd.DisableKeybindings = function()
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

  vim.print("Language number: " .. M.config.lang_num)
end

M.cmd.Dump = function(a)
  local path
  if a == nil or a.args == nil or #a.args == 0 then
    path = vim.fs.joinpath(vim_fn.expand("%:h"), ".interlaced.json")
  else
    path = a.args
  end
  local data = {
    curpos = vim_api.nvim_win_get_cursor(0),
    matches = vim_fn.getmatches(),
    config = {
      language_separator = M.config.language_separator,
      lang_num = M.config.lang_num
    },
  }
  -- the json string will be written to the frist line
  local ok, msg = pcall(vim_fn.writefile, { vim.json.encode(data) }, path, "")
  if ok then
    logger.info("Dumpped at " .. os.date("%H:%M:%S"))
  else
    logger.info(msg)
  end
end

M.cmd.Load = function(a)
  local path
  if a == nil or a.args == nil or #a.args == 0 then
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
    mt._matches = utils.match_list2dict(ret.matches)
  end
  if ret.config ~= nil then
    M.config = vim.tbl_deep_extend("force", M.config, ret.config)
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

---@param opts table
---@return nil
M.setup = function(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    logger.error(string.format("setup() expects table, but got %s:\n%s", type(opts), vim.inspect(opts)))
    opts = {}
  end
  M.config = vim.tbl_deep_extend("force", config, opts)
  rpst.config = M.config

  if M.config.setup_mappings_now then
    M.cmd.EnableKeybindings()
  end

  -- create commands
  -- :h lua-guide-commands-create
  create_command(M.config.cmd_prefix .. "DisableKeybindings", M.cmd.DisableKeybindings, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "Dump", M.cmd.Dump, { complete = "file", nargs = "?" })
  create_command(M.config.cmd_prefix .. "EnableKeybindings", M.cmd.EnableKeybindings, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "InterlaceWithL1", M.cmd.InterlaceWithL1, { complete = "file", nargs = 1 })
  create_command(M.config.cmd_prefix .. "InterlaceWithL2", M.cmd.InterlaceWithL2, { complete = "file", nargs = 1 })
  create_command(M.config.cmd_prefix .. "Load", M.cmd.Load, { complete = "file", nargs = "?" })
  create_command(M.config.cmd_prefix .. "SetLangNum", M.cmd.SetLangNum, { nargs = "?" })
  create_command(M.config.cmd_prefix .. "SetSeparator", M.cmd.SetSeparator, { nargs = "*" })
  create_command(M.config.cmd_prefix .. "ClearMatches", mt.cmd.ClearMatches, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "ListHighlights", mt.cmd.ListHighlights, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "ListMatches", mt.cmd.ListMatches, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "MatchAdd", mt.cmd.MatchAdd, {})
  create_command(M.config.cmd_prefix .. "MatchAddVisual", mt.cmd.MatchAddVisual, { range = true })
  create_command(M.config.cmd_prefix .. "MatchToggle", mt.cmd.MatchToggle, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "DeInterlace", rpst.cmd.DeInterlace, { nargs = 0, range = "%" })
  create_command(M.config.cmd_prefix .. "Interlace", rpst.cmd.Interlace, { nargs = "*", range = "%" })
  create_command(M.config.cmd_prefix .. "NavigateDown", rpst.cmd.NavigateDown, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "NavigateUp", rpst.cmd.NavigateUp, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "NextUnaligned", rpst.cmd.NextUnaligned, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PrevUnaligned", rpst.cmd.PrevUnaligned, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PullBelow", rpst.cmd.PullBelow, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PullBelowPair", rpst.cmd.PullBelowPair, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PushDown", rpst.cmd.PushDown, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PushDownRightPart", rpst.cmd.PushDownRightPart, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PushUp", rpst.cmd.PushUp, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "PushUpPair", rpst.cmd.PushUpPair, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "LeaveAlone", rpst.cmd.LeaveAlone, { nargs = 0 })
  create_command(M.config.cmd_prefix .. "SplitChineseSentences", rpst.cmd.SplitChineseSentences,
    { nargs = 0, range = "%" })
  create_command(M.config.cmd_prefix .. "SplitEnglishSentences", rpst.cmd.SplitEnglishSentences,
    { nargs = 0, range = "%" })
end

return M
