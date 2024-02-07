#!/usr/bin/env lua

local keyset = vim.keymap.set
local setline = vim.fn.setline
local getline = vim.fn.getline
local vim_fn = vim.fn
local vim_api = vim.api
local vim_cmd = vim.cmd
local create_command = vim_api.nvim_create_user_command

local utils = {}
local orig_mappings = {}
local user_conf = {}

function utils.append_to_3_lines_above(lineno)
  local lineno_minus3 = lineno - 3
  local lineno_minus1 = lineno - 1
  local line = getline(lineno)
  local line_minus3 = getline(lineno_minus3)
  local line_minus1 = getline(lineno_minus1)

  local sep = " "
  if line_minus1 == "" or line_minus3 == "" then sep = "" end
  setline(lineno_minus3, line_minus3:gsub("%s+$", "") .. sep .. line)
  setline(lineno, "")
end

function utils.delete_trailing_empty_lines()
  local last_lineno = vim_fn.line("$")
  local buf = vim_api.nvim_get_current_buf()
  while getline(last_lineno):match("^%s*$") do
    vim_fn.deletebufline(buf, last_lineno)
    last_lineno = last_lineno - 1
  end
end

function utils.JoinUp()
  local lineno = vim_fn.line(".")
  if lineno <= 3 then
    print("[interlaced.nvim] Joining too early, please move down your cursor.")
    return
  end

  utils.append_to_3_lines_above(lineno)

  lineno = lineno + 3
  local last_lineno = vim_fn.line("$")
  while lineno <= last_lineno do
    setline(lineno - 3, getline(lineno))
    lineno = lineno + 3
  end
  setline(lineno - 3, "")

  utils.delete_trailing_empty_lines()
  vim_cmd("w")
end

function utils.SplitAtCursor()
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

  utils.delete_trailing_empty_lines()
  vim_cmd("w")
end

function utils.JoinDown()
  vim_cmd([[normal! 0]])
  utils.SplitAtCursor()
end

function utils.NavigateDown()
  vim_cmd([[normal! 03j]])
end

function utils.NavigateUp()
  vim_cmd([[normal! 03k]])
end

function utils.InterlacedSplitHelper(regex)
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

function utils.SplitChineseSentences()
  -- :h split()
  -- Use '\zs' at the end of the pattern to keep the separator.
  -- :echo split('bar:foo', ':\zs')
  local regex = [[\v[…。!！?？—]+[’”"]?\zs]]
  utils.InterlacedSplitHelper(regex)
end

function utils.SplitEnglishSentences()
  local regex = [[\v(%(%(\u\l{,2})@<!(\.\a)@<!\.|[!?])+['’"”]?)%(\s|$)\zs]]
  utils.InterlacedSplitHelper(regex)
end

local function store_orig_mapping(keystroke)
  mapping = vim.fn.maparg(keystroke, "n", false, true)
  orig_mappings[keystroke] = mapping
end

local function setup_mappings()
  local default_mapping_conf = {
    JoinUp = ",",
    SplitAtCursor = "d",
    JoinDown = "D",
    NavigateDown = "J",
    NavigateUp = "K"
  }
  config = vim.tbl_deep_extend("force", default_mapping_conf, user_conf.mappings)

  for func, keystroke in pairs(config) do
    store_orig_mapping(keystroke)
    keyset("n", keystroke, utils[func], { noremap = true, buffer = true, nowait = true })
  end
end

local function unmap_interlaced()
  for keystroke, mapping in pairs(orig_mappings) do
    if vim.tbl_isempty(mapping) then
      vim_api.nvim_buf_del_keymap(0, "n", keystroke)
    else
      mapping.buffer = true
      vim_fn.mapset("n", false, mapping)
    end
  end
end

local function setup_commands()
  create_command("JoinUp", utils.JoinUp, {})
  create_command("SplitAtCursor", utils.SplitAtCursor, {})
  create_command("JoinDown", utils.JoinDown, {})
  create_command("NavigateDown", utils.NavigateDown, {})
  create_command("NavigateUp", utils.NavigateUp, {})

  create_command("SplitChineseSentences", utils.SplitChineseSentences, {})
  create_command("SplitEnglishSentences", utils.SplitEnglishSentences, {})

  create_command("MapInterlaced", setup_mappings, {})
  create_command("UnmapInterlaced", unmap_interlaced, {})
end

local function setup(conf)
  if conf ~= nil then
    user_conf = conf
    if conf.setup_mappings_now then
      setup_mappings()
    end
  end

  setup_commands()
end

return {
  setup = setup
}
