local config = {
  mappings = {
    JoinUp = ",",
    JoinUpPair = "<",
    PullUp = ".",
    PullUpPair = ">",
    SplitAtCursor = "d",
    JoinDown = "D",
    NavigateDown = "J",
    NavigateUp = "K"
  },
  -- automatically enable mappings for *interlaced.txt files, or
  -- otherwise you need to run "MapInterlaced" manually to enable
  -- them
  setup_mappings_now = (((vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())):find("interlaced%.txt$")) ~= nil),
  separator_L1 = "",
  separator_L2 = " ",
  auto_save = true,
}

return config
