# interlaced.nvim

Join/split current line to align bilingual sentence pairs.

## Features

<details>
<summary>
1. Join current line up to previous pair
</summary>
  <p>
    <img src="https://github.com/tanloong/interlaced.nvim/assets/71320000/c3894f0d-2a01-4d56-b243-70abb5b2a827" alt="GIF">
  </p>
</details>

<details>
<summary>
2. Split current line down to the next pair
</summary>
  <p>
    <img src="https://github.com/tanloong/interlaced.nvim/assets/71320000/f324a152-3d45-4a8b-bf29-4c753f2ad199" alt="GIF">
  </p>
</details>

## Installation

+ Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    'tanloong/interlaced.nvim',
    config = function() require("interlaced").setup() end,
    -- Load only for *interlaced.txt, my personal naming habit for parallel text files
    -- Feel free to adjust it as you see fit
    cond = function()
        local bufnr = vim.api.nvim_get_current_buf()
        return (vim.api.nvim_buf_get_name(bufnr)):find("interlaced%.txt$") and true or false
    end
}
```

## Settings

Default configuration:

```lua
require("interlaced").setup({
    -- join current line up to previous pair
    JoinUp = ",",
    -- split current line apart at cursor position
    SplitAtCursor = "d",
    -- join current line down to next pair
    JoinDown = "D",
    -- Navigate to next pair
    NavigateDown = "J",
    -- Navigate to previous pair
    NavigateUp = "K"
})
```

## Sentence segmentation

This plugin has two commands for sentence segmentation in a **monologue** buffer: `SplitEnglishSentences` and `SplitChineseSentences`. Using simple regex patterns to identify sentence boundaries, they cannot handle all cases perfectly. It is recommended to use an NLP tool for the splitting task instead.

## License

GNU GPL v3.0 - see [LICENSE](https://github.com/tanloong/interlaced.nvim/blob/main/LICENSE) for more details.
