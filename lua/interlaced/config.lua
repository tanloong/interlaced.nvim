local rpst = require("interlaced.reposition")
local mt = require("interlaced.match")

local it
local Dump = function()
  it = it or require("interlaced"); it.cmd.Dump()
end
local Load = function()
  it = it or require("interlaced"); it.cmd.Load()
end

local config = {
  keymaps = {
    { "n", ",",     rpst.cmd.PushUp,            { noremap = true, buffer = true, nowait = true } },
    { "n", "<",     rpst.cmd.PushUpPair,        { noremap = true, buffer = true, nowait = true } },
    { "n", ".",     rpst.cmd.PullBelow,         { noremap = true, buffer = true, nowait = true } },
    { "n", ">",     rpst.cmd.PullBelowPair,     { noremap = true, buffer = true, nowait = true } },
    { "n", "d",     rpst.cmd.PushDownRightPart, { noremap = true, buffer = true, nowait = true } },
    { "n", "D",     rpst.cmd.PushDown,          { noremap = true, buffer = true, nowait = true } },
    { "n", "s",     rpst.cmd.LeaveAlone,        { noremap = true, buffer = true, nowait = true } },
    { "n", "[e",    rpst.cmd.SwapWithAbove,     { noremap = true, buffer = true, nowait = true } },
    { "n", "]e",    rpst.cmd.SwapWithBelow,     { noremap = true, buffer = true, nowait = true } },
    { "n", "u",     rpst.cmd.Undo,              { noremap = true, buffer = true, nowait = true } },
    { "n", "<C-r>", rpst.cmd.Redo,              { noremap = true, buffer = true, nowait = true } },
    { "n", "J",     rpst.cmd.NavigateDown,      { noremap = true, buffer = true, nowait = true } },
    { "n", "K",     rpst.cmd.NavigateUp,        { noremap = true, buffer = true, nowait = true } },
    { "n", "md",    Dump,                       { noremap = true, buffer = true, nowait = true } },
    { "n", "ml",    Load,                       { noremap = true, buffer = true, nowait = true } },
    { "n", "gn",    rpst.cmd.NextUnaligned,     { noremap = true, buffer = true, nowait = true } },
    { "n", "gN",    rpst.cmd.PrevUnaligned,     { noremap = true, buffer = true, nowait = true } },
    { "n", "mt",    mt.cmd.MatchToggle,         { noremap = true, buffer = true, nowait = true } },
    { "n", "m;",    mt.cmd.ListMatches,         { noremap = true, buffer = true, nowait = true } },
    { "n", "ma",    mt.cmd.MatchAdd,            { noremap = true, buffer = true, nowait = true } },
    { "v", "ma",    mt.cmd.MatchAddVisual,      { noremap = true, buffer = true, nowait = true } },
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
  enable_keybindings_hook = function()
    -- 1. It costs too much RAM to remember changes of an interlaced buffer,
    --    because re-position changes every line from the cursor below, and the
    --    builtin undo mechanism stores all of that. One `ItPushUp` at the
    --    beginning of an interlaced buffer with 190k lines increases memory
    --    use by 100M. It is recommended to turn off the builtin undo history
    --    to avoid memory creep.
    -- 2. The plugin manages an undo history itself by remembering not the text
    --    changes but re-position operations. You can use that to undo and redo
    --    through e.g., the keybindings set above on `rpst.cmd.Undo` and
    --    `rpst.cmd.Redo`.
    -- 3. Note that the plugin only remembers re-position operations, i.e.,
    --    `ItPushUp(Pair)`, `ItPullBelow(Pair)`, `ItPushDown(RightPart)`, and
    --    `ItLeaveAlone`. Others like `ItInterlace`, `ItDeinterlace` or normal
    --    text changes like inserting, pasting are forgotten, so take care :).
    vim.opt_local.undolevels = -1
  end,
  ---@type function|nil
  disable_keybindings_hook = nil,
}

return config
