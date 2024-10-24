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

## Requirements

+ Neovim >= **0.9.0**

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

https://github.com/tanloong/interlaced.nvim/blob/a29139456f39e1fa52a44c7fb6a05b447dee2c4c/lua/interlaced/config.lua#L1-L19

## Commands

- `SplitEnglishSentences` and `SplitChineseSentences`: These commands are used for sentence segmentation in a **monolingual** buffer. It is important to note that they may not handle all cases perfectly, as they use simple regex patterns to identify sentence boundaries. For more accurate splitting, it is recommended to use an NLP tool. However, if you just want a quick and not-that-accurate splitting, these commands can be helpful.

- `MapInterlaced` and `UnmapInterlaced`: `MapInterlaced` sets keybindings for text manipulations; `UnmapInterlaced` restores them to their previous mappings, if any.

- `InterlaceWithL1` and `InterlaceWithL2`: Take lines from the current buffer and interlaces them with lines from a specified file, forming an array of `(l1, l2)` pairs. These commands also filter out any empty lines from both the buffer and the file to ensure that only non-empty lines are interlaced. The resulting interlaced text is then saved to a new file and opened for further editing. After openning the interlaced file, keybindings are setup if they have not been previously.
