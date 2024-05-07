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
    config = function()
        opts = {
            mappings = {
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
            },

            setup_mappings_now = false,
        }
        local bufnr = vim.api.nvim_get_current_buf()
        -- automatically enable mappings for *interlaced.txt files, or
        -- otherwise you need to run "MapInterlaced" manually to enable
        -- them
        local is_interlaced_file = (vim.api.nvim_buf_get_name(bufnr)):find("interlaced%.txt$")
        if is_interlaced_file then
            opts["setup_mappings_now"] = true
        end
        require("interlaced").setup(opts)
    end,
    ft = "text",
}
```

+ Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
require("lazy").setup({
    {
        'tanloong/interlaced.nvim',
        config = function()
            opts = {
                mappings = {
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
                },

                setup_mappings_now = false,
                separator_L1 = "",
                separator_L2 = " ",
            }
            local bufnr = vim.api.nvim_get_current_buf()
            -- automatically enable mappings for *interlaced.txt files, or
            -- otherwise you need to run "MapInterlaced" manually to enable
            -- them
            local is_interlaced_file = (vim.api.nvim_buf_get_name(bufnr)):find("interlaced%.txt$")
            if is_interlaced_file then
                opts["setup_mappings_now"] = true
            end
            require("interlaced").setup(opts)
        end,
        ft = "text",
    },
})
```

## Commands

- `SplitEnglishSentences` and `SplitChineseSentences`: These commands are used for sentence segmentation in a **monolingual** buffer. It is important to note that they may not handle all cases perfectly, as they rely on simple regex patterns to identify sentence boundaries. For more accurate splitting, it is recommended to use an NLP tool. However, if you don't have an NLP tool at hand or if you just want a quick and not-that-accurate splitting, these commands can be helpful.

- `MapInterlaced` and `UnmapInterlaced`: `MapInterlaced` sets keybindings for text manipulations; `UnmapInterlaced` restores them to their previous mapping.

| Manipulation | Default keybinding |
|-|-|
| JoinUp | `,` |
| JoinDown | `D` |
| SplitAtCursor | `d` |
| NavigateUp | `J` |
| NavigateDown | `K` |
