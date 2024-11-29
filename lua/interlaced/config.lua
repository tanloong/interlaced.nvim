local config = {
  mappings = {
    [","] = require("interlaced.reposition").cmd.PushUp,
    ["<"] = require("interlaced.reposition").cmd.PushUpPair,
    ["."] = require("interlaced.reposition").cmd.PullBelow,
    [">"] = require("interlaced.reposition").cmd.PullBelowPair,
    ["d"] = require("interlaced.reposition").cmd.PushDownRightPart,
    ["D"] = require("interlaced.reposition").cmd.PushDown,
    ["J"] = require("interlaced.reposition").cmd.NavigateDown,
    ["K"] = require("interlaced.reposition").cmd.NavigateUp,
    ["md"] = require("interlaced.reposition").cmd.Dump,
    ["ml"] = require("interlaced.reposition").cmd.Load,
    ["gn"] = require("interlaced.reposition").cmd.NextUnaligned,
    ["gN"] = require("interlaced.reposition").cmd.PrevUnaligned,
    ["mt"] = require("interlaced.match").cmd.MatchToggle,
    ["m;"] = require("interlaced.match").cmd.ListMatches,
  },
  -- automatically enable mappings for *interlaced.txt files
  setup_mappings_now = (((vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())):find("interlaced%.txt$")) ~= nil),
  -- sentence separator to insert between when push- or pull-ing up
  language_separator = { ["1"] = "", ["2"] = " " },
  -- save on text reposition, i.e., pushing, pulling, sentence splitting.
  auto_save = true,
  cmd_prefix = "It",
  lang_num = 2,
  ---@type function|nil
  enable_keybindings_hook = nil,
  ---@type function|nil
  disable_keybindings_hook = nil,
}

return config
