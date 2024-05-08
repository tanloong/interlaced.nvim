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

+ Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'tanloong/interlaced.nvim',
  config = function()
    require("interlaced").setup()
    -- or setup with your own config (see Configuration in README)
    -- require("interlaced").setup(config)
  end,
  ft = "text",
},
```
## Configuration

Bellow is a linked snippet with the default values.

https://github.com/tanloong/interlaced.nvim/blob/a74a72dcfc3a4a5208ace8cfbcf8c182e779c4fa/lua/interlaced/config.lua#L1-L18

## Commands

- `SplitEnglishSentences` and `SplitChineseSentences`: These commands are used for sentence segmentation in a **monolingual** buffer. It is important to note that they may not handle all cases perfectly, as they rely on simple regex patterns to identify sentence boundaries. For more accurate splitting, it is recommended to use an NLP tool. However, if you don't have an NLP tool at hand or if you just want a quick and not-that-accurate splitting, these commands can be helpful.

- `MapInterlaced` and `UnmapInterlaced`: `MapInterlaced` sets keybindings for text manipulations; `UnmapInterlaced` restores them to their previous mapping.
