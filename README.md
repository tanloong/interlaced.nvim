# interlaced.nvim

A minimal neovim plugin that provides keybindings for aligning bilingual sentence pairs.

## Features

1. Join misaligned pair up to the above one
2. Split misaligned pair at cursor location
3. The file will be saved automatically after joining or splitting.

## Installation

+ Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use { 'tanloong/interlaced.nvim',
    cond = function() return string.find(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()), "interlaced.*%.txt$") and true or false end,
    config = function() require("interlaced").setup() end,
```

## License

GPL v3
