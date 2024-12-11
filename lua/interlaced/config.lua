local rpst = require("interlaced.reposition")
local mt = require("interlaced.match")

local it
local Dump = function() it = it or require("interlaced"); it.cmd.Dump() end
local Load = function() it = it or require("interlaced"); it.cmd.Load() end

local config = {
  keymaps = {
    { "n", ",",  rpst.cmd.PushUp,            { noremap = true, buffer = true, nowait = true } },
    { "n", "<",  rpst.cmd.PushUpPair,        { noremap = true, buffer = true, nowait = true } },
    { "n", ".",  rpst.cmd.PullBelow,         { noremap = true, buffer = true, nowait = true } },
    { "n", ">",  rpst.cmd.PullBelowPair,     { noremap = true, buffer = true, nowait = true } },
    { "n", "d",  rpst.cmd.PushDownRightPart, { noremap = true, buffer = true, nowait = true } },
    { "n", "D",  rpst.cmd.PushDown,          { noremap = true, buffer = true, nowait = true } },
    { "n", "s",  rpst.cmd.LeaveAlone,        { noremap = true, buffer = true, nowait = true } },
    { "n", "J",  rpst.cmd.NavigateDown,      { noremap = true, buffer = true, nowait = true } },
    { "n", "K",  rpst.cmd.NavigateUp,        { noremap = true, buffer = true, nowait = true } },
    { "n", "md", Dump,                       { noremap = true, buffer = true, nowait = true } },
    { "n", "ml", Load,                       { noremap = true, buffer = true, nowait = true } },
    { "n", "gn", rpst.cmd.NextUnaligned,     { noremap = true, buffer = true, nowait = true } },
    { "n", "gN", rpst.cmd.PrevUnaligned,     { noremap = true, buffer = true, nowait = true } },
    { "n", "mt", mt.cmd.MatchToggle,         { noremap = true, buffer = true, nowait = true } },
    { "n", "m;", mt.cmd.ListMatches,         { noremap = true, buffer = true, nowait = true } },
    { "n", "ma", mt.cmd.MatchAdd,            { noremap = true, buffer = true, nowait = true } },
    { "v", "ma", mt.cmd.MatchAddVisual,      { noremap = true, buffer = true, nowait = true } },
  },
  -- automatically enable mappings for *interlaced.txt files
  setup_mappings_now = (((vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())):find("interlaced%.txt$")) ~= nil),
  -- sentence separator to insert between when push- or pull-ing up
  language_separator = { ["1"] = "", ["2"] = " " },
  -- save on text re-position, i.e., pushing, pulling, sentence splitting. But causes delay for re-position, better turn this off
  auto_save = false,
  cmd_prefix = "It",
  lang_num = 2,
  ---@type function|nil
  enable_keybindings_hook = nil,
  ---@type function|nil
  disable_keybindings_hook = nil,
}

return config
