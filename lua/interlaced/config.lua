local rpst = require("interlaced.reposition")
local mt = require("interlaced.match")

local it
local dump = function()
  it = it or require("interlaced"); it.cmd.dump()
end
local load = function()
  it = it or require("interlaced"); it.cmd.load()
end

local config = {
  keymaps = {
    { "n", ",",  rpst.cmd.push_up,              { noremap = true, buffer = true, nowait = true } },
    { "n", "<",  rpst.cmd.push_up_pair,         { noremap = true, buffer = true, nowait = true } },
    { "n", "e",  rpst.cmd.push_up_left_part,    { noremap = true, buffer = true, nowait = true } },
    { "n", ".",  rpst.cmd.pull_below,           { noremap = true, buffer = true, nowait = true } },
    { "n", ">",  rpst.cmd.pull_below_pair,      { noremap = true, buffer = true, nowait = true } },
    { "n", "d",  rpst.cmd.push_down_right_part, { noremap = true, buffer = true, nowait = true } },
    { "n", "D",  rpst.cmd.push_down,            { noremap = true, buffer = true, nowait = true } },
    { "n", "s",  rpst.cmd.leave_alone,          { noremap = true, buffer = true, nowait = true } },
    { "n", "[e", rpst.cmd.swap_with_above,      { noremap = true, buffer = true, nowait = true } },
    { "n", "]e", rpst.cmd.swap_with_below,      { noremap = true, buffer = true, nowait = true } },
    { "n", "U",  rpst.cmd.undo,                 { noremap = true, buffer = true, nowait = true } },
    { "n", "R",  rpst.cmd.redo,                 { noremap = true, buffer = true, nowait = true } },
    { "n", "J",  rpst.cmd.navigate_down,        { noremap = true, buffer = true, nowait = true } },
    { "n", "K",  rpst.cmd.navigate_up,          { noremap = true, buffer = true, nowait = true } },
    { "n", "md", dump,                          { noremap = true, buffer = true, nowait = true } },
    { "n", "ml", load,                          { noremap = true, buffer = true, nowait = true } },
    { "n", "gn", rpst.cmd.next_unaligned,       { noremap = true, buffer = true, nowait = true } },
    { "n", "gN", rpst.cmd.prev_unaligned,       { noremap = true, buffer = true, nowait = true } },
    { "n", "mt", mt.cmd.match_toggle,           { noremap = true, buffer = true, nowait = true } },
    { "n", "m;", mt.cmd.list_matches,           { noremap = true, buffer = true, nowait = true } },
    { "n", "ma", mt.cmd.match_add,              { noremap = true, buffer = true, nowait = true } },
    { "v", "ma", mt.cmd.match_add_visual,       { noremap = true, buffer = true, nowait = true } },
  },
  -- automatically enable mappings for *interlaced.txt files
  setup_mappings_now = (((vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())):find("interlaced%.txt$")) ~= nil),
  -- sentence separator to insert between when push- or pull-ing up
  language_separator = { ["1"] = "", ["2"] = " " },
  lang_num = 2,
  ---@type function|nil
  enable_keybindings_hook = function()
    -- TODO: rationale
    vim.opt_local.undofile = false

    vim.opt_local.signcolumn = "no"
    vim.opt_local.relativenumber = false
    vim.opt_local.number = false
    require "interlaced".ShowChunkNr()

    -- load ./.interlaced.json if any
    require "interlaced".cmd.load()
  end,
  ---@type function|nil
  disable_keybindings_hook = nil,
}

return config
