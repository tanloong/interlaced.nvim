# interlaced.nvim

Join or split current line for aligning bilingual sentence pairs.

## Features

1. Join current line up to previous pair

![simplescreenrecorder-2023-08-12_03 11 42](https://github.com/tanloong/interlaced.nvim/assets/71320000/c3894f0d-2a01-4d56-b243-70abb5b2a827)

2. Split current line down to the next pair

![simplescreenrecorder-2023-08-12_03 14 57](https://github.com/tanloong/interlaced.nvim/assets/71320000/f324a152-3d45-4a8b-bf29-4c753f2ad199)

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
    cond = function()
        return (vim.api.nvim_buf_get_name(bufnr)):find("interlaced%.txt$") and true or false
    end
}
```

## Configuration

```lua
return require("interlaced").setup({
    InterlacedJoinUp = ",",               
    InterlacedSplitDownAtCursor = "d",    
    InterlacedSplitDownTheWholeLine = "D",
    InterlacedNavDown = "J",              -- move cursor to next pair
    InterlacedNavUp = "K"                 -- move curosr to previous pair
})
```

## License

GPL v3
