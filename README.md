# interlaced.nvim

Join or split current line for aligning bilingual sentence pairs.

## Features

1. Join current line up to previous pair

2. Split current line down to the next pair

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
