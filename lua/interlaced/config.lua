local rpst = require("interlaced.reposition")
local mt = require("interlaced.match")

local it
local dump = function()
  it = it or require("interlaced"); it.cmd.dump()
end
local load = function()
  it = it or require("interlaced"); it.cmd.load()
end

local opt = { noremap = true, buffer = true, nowait = true }
local default = {
  keymaps = {
    { "n", ",",  rpst.cmd.push_up,              opt },
    { "n", "<",  rpst.cmd.push_up_pair,         opt },
    { "n", "e",  rpst.cmd.push_up_left_part,    opt },
    { "n", ".",  rpst.cmd.pull_below,           opt },
    { "n", ">",  rpst.cmd.pull_below_pair,      opt },
    { "n", "d",  rpst.cmd.push_down_right_part, opt },
    { "n", "D",  rpst.cmd.push_down,            opt },
    { "n", "s",  rpst.cmd.leave_alone,          opt },
    { "n", "[e", rpst.cmd.swap_with_above,      opt },
    { "n", "]e", rpst.cmd.swap_with_below,      opt },
    { "n", "U",  rpst.cmd.undo,                 opt },
    { "n", "R",  rpst.cmd.redo,                 opt },
    { "n", "J",  rpst.cmd.navigate_down,        opt },
    { "n", "K",  rpst.cmd.navigate_up,          opt },
    { "n", "md", dump,                          opt },
    { "n", "ml", load,                          opt },
    { "n", "gn", rpst.cmd.next_unaligned,       opt },
    { "n", "gN", rpst.cmd.prev_unaligned,       opt },
    { "n", "mt", mt.cmd.match_toggle,           opt },
    { "n", "m;", mt.cmd.list_matches,           opt },
    { "n", "ma", mt.cmd.match_add,              opt },
    { "v", "ma", mt.cmd.match_add_visual,       opt },
  },
  -- sentence separator to insert between when push- or pull-ing up
  language_separator = { ["1"] = "", ["2"] = " " },
  lang_num = 2,
  ---@type function|nil
  enable_keybindings_hook = function()
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

return default
