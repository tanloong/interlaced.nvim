local config = {
  mappings = {
    PushUp = ",",
    PushUpPair = "<",
    PullBelow = ".",
    PullBelowPair = ">",
    PushDownRightPart = "d",
    PushDown = "D",
    NavigateDown = "J",
    NavigateUp = "K"
  },
  -- automatically enable mappings for *interlaced.txt files
  setup_mappings_now = (((vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())):find("interlaced%.txt$")) ~= nil),
  -- sentence separator to insert between when push- or pull-ing up
  language_separator = { ["1"] = "", ["2"] = " " },
  language_weight = { ["1"] = 2, ["2"] = 1 },
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
