#!/usr/bin/env lua

local keyset = vim.keymap.set
local vim_fn = vim.fn
local vim_api = vim.api
local vim_cmd = vim.cmd

local config = require("interlaced.config")
local mt = require("interlaced.match")
local rpst = require("interlaced.reposition")
local utils = require("interlaced.utils")
local logger = require("interlaced.logger")
local _io = require("interlaced._io")
local _str = require("interlaced._str")

-- The StartLux and DeepSeek clients keep their own options and state; requiring
-- them here adds their actions to the `:Interlaced` dispatcher:
--   startlux_op / startlux_apply / startlux_cancel / startlux_prompt
--   deepseek / deepseek_status / deepseek_cancel
-- `require` is cached, so repeated `:Interlaced reload` is harmless.
local startlux = require("interlaced.startlux")
local deepseek = require("interlaced.deepseek")

local _H = {}
local M = {
  _H = _H,
  -- buffer-local state, keyed by buffer number
  _orig_mappings = {},   -- [bufnr] = list of mappings replaced by enable_keybindings
  _is_mappings_on = {},  -- [bufnr] = boolean
  _showing_chunknr = {}, -- [bufnr] = boolean
  _chunknr_relative = false, -- global: show relative chunk numbers
  _chunknr_state = {},   -- [bufnr] = last drawn range/mode
  _ns_id = nil,
  action = {},
}

if vim_fn.has("nvim-0.12") == 0 then
  logger.error("interlaced.nvim requires Neovim >= 0.12.0")
  return M
end

vim_api.nvim_create_autocmd("BufDelete", {
  group = vim_api.nvim_create_augroup("interlaced_init", { clear = true }),
  callback = function(args)
    M._orig_mappings[args.buf] = nil
    M._is_mappings_on[args.buf] = nil
    M._showing_chunknr[args.buf] = nil
    M._chunknr_state[args.buf] = nil
  end,
})

---Whether the given buffer currently has interlaced keybindings enabled.
---@param buf integer
---@return boolean
_H.mappings_on = function(buf)
  return M._is_mappings_on[buf] == true
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
  local interlaced_path = vim_fn.tempname() .. ".interlaced.txt"
  vim_fn.writefile(lines, interlaced_path)
  vim_cmd({ cmd = "edit", args = { interlaced_path } })
  if not _H.mappings_on(vim_api.nvim_get_current_buf()) then
    M.action.enable_keybindings()
  end
end

---@param params table
---@return nil
M.action.interlace_with_l1 = function(params)
  _H.InterlaceWithL(params, false)
end

---@param params table
---@return nil
M.action.interlace_with_l2 = function(params)
  _H.InterlaceWithL(params, true)
end

---Interlace current buffer with files, placing current buffer at position {n}
---@param a table
---@return nil
M.action.interlace_as_l = function(a)
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
  local interlaced_path = vim_fn.tempname() .. ".interlaced.txt"
  vim_fn.writefile(interlaced_lines, interlaced_path)
  vim_cmd({ cmd = "edit", args = { interlaced_path } })

  -- Keep `lang_num` in sync so `:Interlaced deinterlace` and the re-positioning
  -- actions use the same chunk size as the freshly created buffer.
  rpst._H.set_lang_num(#a.fargs + 1)
  -- Enable keybindings if not already enabled
  if not _H.mappings_on(vim_api.nvim_get_current_buf()) then
    M.action.enable_keybindings()
  end
end

---Enable custom keybindings as defined in config.mappings.
M.action.enable_keybindings = function()
  local buf = vim_api.nvim_get_current_buf()
  if type(config.enable_keybindings_hook) == "function" then config.enable_keybindings_hook() end
  if _H.mappings_on(buf) then
    logger.warning("Keybindings already on, nothing to do")
    return
  end
  if config.keymaps == nil then return end

  M._orig_mappings[buf] = {}
  local action, mode, lhs, action_name
  for _, t in ipairs(config.keymaps) do
    mode, lhs, action_name = unpack(t)
    for _, provider in ipairs({ rpst, mt, M, startlux, deepseek }) do action = provider.action[action_name]; if action ~= nil then break end end
    if action ~= nil then
      _H.store_orig_mapping(buf, lhs, mode); keyset(mode, lhs, action, {noremap = true, buffer = true, nowait = true})
    else logger.error("Unknown action name: " .. tostring(action_name)) end
  end
  logger.info("Keybindings on")
  M._is_mappings_on[buf] = true
end

---Disable all keybindings set by EnableKeybindings.
M.action.disable_keybindings = function()
  local buf = vim_api.nvim_get_current_buf()
  if type(config.disable_keybindings_hook) == "function" then config.disable_keybindings_hook() end
  if not _H.mappings_on(buf) then
    logger.warning("Keybindings already off, nothing to do")
    return
  end
  if config.keymaps ~= nil then
    local mode, lhs
    for _, entry in ipairs(config.keymaps) do
      mode, lhs = unpack(entry)
      pcall(vim_api.nvim_buf_del_keymap, buf, mode, lhs)
    end
  end
  for _, mapargs in ipairs(M._orig_mappings[buf] or {}) do
    if next(mapargs) ~= nil then
      mapargs.buffer = true
      vim_fn.mapset(mapargs)
    end
  end
  logger.info("Keybindings off")
  M._is_mappings_on[buf] = false
  M._orig_mappings[buf] = {}
end

---Show only the plugin's chunk numbers: turn off the system line-number
---columns in every window displaying `buf`.
---@param buf integer
_H.disable_system_linenumbers = function(buf)
  for _, win in ipairs(vim_fn.win_findbuf(buf)) do
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
  end
end

M.ShowChunkNr = function()
  local buf = vim_api.nvim_get_current_buf()
  _H.disable_system_linenumbers(buf)
  if M._showing_chunknr[buf] == true then return end
  if M._ns_id == nil then M._ns_id = vim_api.nvim_create_namespace("interlaced") end

  M._showing_chunknr[buf] = true
  M._chunknr_state[buf] = nil
  M.RefreshChunkNr()
end

---Redraw the chunk numbers of the current buffer. In absolute mode every chunk
---is numbered once; in relative mode only the chunks visible in the current
---window are numbered, with the cursor chunk absolute and the others relative
---to it.
M.RefreshChunkNr = function()
  local buf = vim_api.nvim_get_current_buf()
  if M._showing_chunknr[buf] ~= true then return end
  if M._ns_id == nil then M._ns_id = vim_api.nvim_create_namespace("interlaced") end

  local relative = M._chunknr_relative == true
  local chunk_size = config.lang_num + 1
  local last_lineno = vim_api.nvim_buf_line_count(buf)
  local first_line = math.max(1, vim_fn.line("w0"))
  local last_line = math.max(first_line, vim_fn.line("w$"))
  local cursor_line = vim_fn.line(".")
  local current_chunk = math.floor((cursor_line - 1) / chunk_size) + 1

  -- A chunk number lives on the blank separator after the chunk, so chunk `n`
  -- needs line `n * chunk_size` to exist.
  local first_mark, last_mark
  if relative then
    first_mark = math.max(1, math.ceil(first_line / chunk_size))
    last_mark = math.min(math.floor(last_lineno / chunk_size), math.floor(last_line / chunk_size))
  else
    first_mark = 1
    last_mark = math.floor(last_lineno / chunk_size)
  end

  local mode = relative and "relative" or "absolute"
  local state = M._chunknr_state[buf]
  if state
    and state.mode == mode
    and state.first == first_mark
    and state.last == last_mark
    and state.lang_num == config.lang_num
    and state.line_count == last_lineno
    and (not relative or state.current == current_chunk) then
    return
  end

  vim_api.nvim_buf_clear_namespace(buf, M._ns_id, 0, -1)
  if first_mark <= last_mark then
    local opts = { right_gravity = true, virt_text_win_col = 0, hl_mode = "combine" }
    for chunkno = first_mark, last_mark do
      local label = chunkno
      if relative and chunkno ~= current_chunk then
        label = math.abs(chunkno - current_chunk)
      end
      opts.virt_text = { { string.format("%s ", label), "LineNr" } }
      vim_api.nvim_buf_set_extmark(buf, M._ns_id, chunkno * chunk_size - 1, 0, opts)
    end
  end

  M._chunknr_state[buf] = {
    mode = mode,
    first = first_mark,
    last = last_mark,
    current = current_chunk,
    lang_num = config.lang_num,
    line_count = last_lineno,
  }
end

M.ClearChunkNr = function()
  local buf = vim_api.nvim_get_current_buf()
  if M._ns_id ~= nil then
    vim_api.nvim_buf_clear_namespace(buf, M._ns_id, 0, -1)
  end
  M._showing_chunknr[buf] = false
  M._chunknr_state[buf] = nil
end

local chunknr_group = vim_api.nvim_create_augroup("interlaced_chunknr", { clear = true })
local function refresh_chunknr()
  if M._showing_chunknr[vim_api.nvim_get_current_buf()] then M.RefreshChunkNr() end
end
local function enter_chunknr_window()
  local buf = vim_api.nvim_get_current_buf()
  if M._showing_chunknr[buf] then
    _H.disable_system_linenumbers(buf)
    M.RefreshChunkNr()
  end
end
vim_api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinScrolled" }, {
  group = chunknr_group,
  callback = refresh_chunknr,
})
vim_api.nvim_create_autocmd("BufWinEnter", {
  group = chunknr_group,
  callback = enter_chunknr_window,
})
vim_api.nvim_create_autocmd("WinEnter", {
  group = chunknr_group,
  callback = refresh_chunknr,
})
vim_api.nvim_create_autocmd("VimResized", {
  group = chunknr_group,
  callback = refresh_chunknr,
})

M.action.toggle_chunk_number = function()
  local buf = vim_api.nvim_get_current_buf()
  if M._showing_chunknr[buf] then
    M.ClearChunkNr()
  else
    M.ShowChunkNr()
  end
end

---Switch the chunk numbers between absolute and relative.
M.action.toggle_chunk_number_relative = function()
  M._chunknr_relative = not M._chunknr_relative
  local current_win = vim_api.nvim_get_current_win()
  local wins = { current_win }
  for _, win in ipairs(vim_api.nvim_list_wins()) do
    if win ~= current_win then table.insert(wins, win) end
  end
  local refreshed = {}
  for _, win in ipairs(wins) do
    local buf = vim_api.nvim_win_get_buf(win)
    if M._showing_chunknr[buf] and not refreshed[buf] then
      refreshed[buf] = true
      M._chunknr_state[buf] = nil
      vim_api.nvim_win_call(win, function() M.RefreshChunkNr() end)
    end
  end
  logger.info(("Chunk numbers: %s"):format(M._chunknr_relative and "relative" or "absolute"))
end

M.action.set_separator = function(a)
  -- :ItSetSeparator ?
  -- :ItSetSeparator
  if #a.fargs == 0 or a.args == "?" then
    for _, l in ipairs(vim_fn.sort(vim.tbl_keys(config.language_separator))) do
      vim.print(("L%s: '%s'"):format(l, config.language_separator[l]))
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

  config.language_separator[tostring(l)] = sep
  vim.print(("L%s separator: '%s'"):format(l, sep))
end

---@param n nil|string|number
M.action.set_lang_num = function(n)
  -- :ItSetLangNum ?
  -- :ItSetLangNum
  if n == nil or n == "?" then
    vim.print(("Language number: %s"):format(config.lang_num))
    return
  end

  -- :Interlaced set_lang_num {int}
  n = tonumber(n)
  if n == nil or n < 1 then
    logger.error("Language number must be a positive integer")
    return
  end
  rpst._H.set_lang_num(n)

  M.ClearChunkNr()
  M.ShowChunkNr()

  vim.print(("Language number: %s"):format(config.lang_num))
end

M.action.dump = function(path)
  if path == nil then
    path = vim.fs.joinpath(vim_fn.expand("%:h"), ".interlaced.json")
  end
  local data = {
    curpos = vim_api.nvim_win_get_cursor(0),
    matches = vim_fn.getmatches(),
    config = {
      language_separator = config.language_separator,
      lang_num = config.lang_num
    },
  }

  if not _io.write(path, vim.json.encode(data, { indent = " " })) then return end
  logger.info(("dumpped at %s"):format(os.date("%H:%M:%S")))
end

M.action.load = function(a)
  local path
  if a == nil or a.args == nil or #a.args == 0 then
    path = vim.fs.joinpath(vim_fn.expand("%:h"), ".interlaced.json")
  else
    path = a.args
  end

  local data = _io.read(path)
  if data == nil then return end

  local ok, ret = pcall(vim.json.decode, data)
  if not ok then return end

  if ret.curpos ~= nil then
    vim_api.nvim_win_set_cursor(0, ret.curpos)
  end
  if ret.matches ~= nil then
    vim_fn.setmatches(ret.matches)
    mt._matches = utils.match_list2dict(ret.matches)
  end
  if ret.config ~= nil then
    local metatable = getmetatable(config)
    config = vim.tbl_deep_extend("force", config, ret.config)
    setmetatable(config, metatable)
    -- share one config table with `reposition`; keeping separate copies made
    -- later mutations (e.g. set_lang_num) invisible to each other
    rpst.config = config
  end
end

---@param buf integer
---@param key string
---@param mode string|string[]
---@return nil
_H.store_orig_mapping = function(buf, key, mode)
  local mappings = M._orig_mappings[buf]
  if type(mode) == "string" then
    table.insert(mappings, vim_fn.maparg(key, mode, false, true))
  else
    for _, m in ipairs(mode) do
      table.insert(mappings, vim_fn.maparg(key, m, false, true))
    end
  end
end

M.action.reload = function()
  local pkg_name = "interlaced"
  -- drop the extmarks added by the old module before unloading it
  require(pkg_name).ClearChunkNr()
  for k, _ in pairs(package.loaded) do
    if k:sub(1, #pkg_name) == pkg_name then
      package.loaded[k] = nil
    end
  end
  require(pkg_name)
  vim.print(("%s restarted at %s"):format(pkg_name, os.date("%H:%M:%S")))
end

vim_api.nvim_create_user_command("Interlaced", function(a)
  local action
  for _, provider in ipairs({ rpst, mt, M, startlux, deepseek }) do
    action = provider.action[a.fargs[1]]
    if action ~= nil then break end
  end
  if action ~= nil then
    a.args = vim.trim(_str.removeprefix(a.args, a.fargs[1]))
    table.remove(a.fargs, 1)
    return action(a)
  else
    logger.error(string.format("subcommand '%s' not found", tostring(a.fargs[1])))
  end
end, {
  complete = function(_, line)
    local candidates = vim.iter({ rpst.action, mt.action, M.action, startlux.action, deepseek.action }):map(vim.tbl_keys):flatten():totable()
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

return M
