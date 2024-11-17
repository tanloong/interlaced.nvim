# interlaced.nvim

Line repositioning for bilingual sentence alignment.

## Features

<details>
<summary>
1. Push current line up to previous pair
</summary>
  <p>
    <img src="https://github.com/tanloong/interlaced.nvim/assets/71320000/c3894f0d-2a01-4d56-b243-70abb5b2a827" alt="GIF">
  </p>
</details>

<details>
<summary>
2. Push current line down to the next pair
</summary>
  <p>
    <img src="https://github.com/tanloong/interlaced.nvim/assets/71320000/f324a152-3d45-4a8b-bf29-4c753f2ad199" alt="GIF">
  </p>
</details>

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
        separator_L1 = "",
        separator_L2 = " ",
        -- save on text reposition, i.e., pushing, pulling, sentence splitting.
        auto_save = true,
        cmd_prefix = "It",
      }
    )
  end,
  ft = "text",
}
```

## Commands

- `:ItSplitEnglishSentences`, `:ItSplitChineseSentences`: Identify sentence boundaries and insert a newline between them. Work linewise on the range when provided, the whole buffer if not.

- `:ItMapInterlaced`, `:ItUnmapInterlaced`: `:MapInterlaced` sets keybindings for text manipulations; `UnmapInterlaced` restores them to their previous mappings, if any.

- `:ItInterlaceWithL1`, `:ItInterlaceWithL2`: Take lines from the current buffer and interlaces them with lines from a specified file, forming an array of `(l1, l2)` pairs. Empty lines are filtered out. The resulting interlaced text is then saved to a new file and opened, then keybindings are setup if they have not been previously.
