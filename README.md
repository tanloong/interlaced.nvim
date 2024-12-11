# interlaced.nvim

Line repositioning for bilingual sentence alignment.

## Requirements

+ Neovim >= **0.9.0**

## Installation

+ Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "tanloong/interlaced.nvim",
  config = function()
    require("interlaced").setup(
      {
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
        separators = { ["1"] = "", ["2"] = " " },
        -- save on text reposition, i.e., pushing, pulling, sentence splitting.
        auto_save = true,
        cmd_prefix = "It",
        lang_num = 2,
      }
    )
  end,
  ft = "text",
}
```

## Commands

**ItEnableKeybindings** applys `keymaps` in config. Original keymaps are backed up.

**ItDisableKeybindings** cancels `keymaps` in config and restores backed up keymaps.

- `:ItSplitEnglishSentences`, `:ItSplitChineseSentences`: Identify sentence endings and insert a newline after each of them. Work linewise on the range when provided, the whole buffer if not.

- `:ItInterlaceWithL1`, `:ItInterlaceWithL2`: Take lines from the current buffer and interlaces them with lines from a specified file, forming an array of `(l1, l2)` pairs. Empty lines are filtered out. The resulting interlaced text is then saved to a new file and opened, then keybindings are setup if they have not been previously.
