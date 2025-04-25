local default = {
  keymaps = {
    {"n", "]", "push_up"},
    {"n", "<", "push_up_pair"},
    {"n", "e", "push_up_left_part"},
    {"n", ".", "pull_below"},
    {"n", ">", "pull_below_pair"},
    {"n", "d", "push_down_right_part"},
    {"n", "D", "push_down"},
    {"n", "s", "leave_alone"},
    {"n", "[e", "swap_with_above"},
    {"n", "]e", "swap_with_below"},
    {"n", "U", "undo"},
    {"n", "R", "redo"},
    {"n", "J", "navigate_down"},
    {"n", "K", "navigate_up"},
    {"n", "md", "dump"},
    {"n", "ml", "load"},
    {"n", "gn", "next_unaligned"},
    {"n", "gN", "prev_unaligned"},
    {"n", "mt", "match_toggle"},
    {"n", "m;", "list_matches"},
    {"n", "ma", "match_add"},
    {"v", "ma", "match_add_visual"},
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
    require "interlaced".action.load()
  end,
  ---@type function|nil
  disable_keybindings_hook = nil,
  ---@type boolean
  sound_feedback = false,
}

local config = {}
setmetatable(config, {
  __index = function(_, key)
    if vim.g.interlaced and vim.g.interlaced[key] ~= nil then
      return vim.g.interlaced[key]
    else
      return default[key]
    end
  end
})

return config
