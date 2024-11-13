local config = {
  mappings = {
    PushUp = ",",
    PushUpPair = "<",
    PullUp = ".",
    PullUpPair = ">",
    PushDownRightPart = "d",
    PushDown = "D",
    NavigateDown = "J",
    NavigateUp = "K"
  },
  -- automatically enable mappings for *interlaced.txt files
  setup_mappings_now = (((vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())):find("interlaced%.txt$")) ~= nil),
  -- sentence separator to insert between when push- or pull-ing up
  separator_L1 = "",
  separator_L2 = " ",
  -- save on text reposition, i.e., pushing, pulling, sentence splitting.
  auto_save = true,
  cmd_prefix = "It",
}

return config
