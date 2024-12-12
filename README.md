# interlaced.nvim

Text re-positioning for bilingual sentence alignment.

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

**:ItEnableKeybindings** applies keybindings specified in the `mappings` field of the table passed to `require("interlaced").setup()`. Original keymaps are backed up.

**:ItDisableKeybindings** cancels `mappings` keybindings and restores backed up keymaps.

**:ItSplitEnglishSentences** identifies English sentence endings and insert a newline after each of them. Works linewise on the range when provided, the whole buffer if not.

**:ItSplitChineseSentences** ibidem but identifies Chinese sentence endings.

**:ItInterlaceWithL1 {filepath}** mixes non-empty lines from current buffer with those from `filepath` into empty-line-separated pairs of lines. In each pair, lines from `filepath` are above those from current buffer. `mappings` keybindings are enabled if they have not been previously.

**:ItInterlaceWithL2 {filepath}** ibidem but lines from `filepath` are below those from current buffer.

**:[range]ItInterlace [num]** mixes non-empty lines from current buffer into `num` empty-line-separated groups. If `num` is not provided, `lang_num` field of the config table will be used. Works on the range when provided, the whole buffer if not.

**:ItMatchAdd** opens a matches window to edit a pattern to be highlighted. The window has 3 columns: match id, highlight group, and pattern. On pressing `<Enter>` in insert/normal mode, this plugin will call `matchadd()` with the 3 values (see `:h matchadd()`). If match id is left as `_`, this plugin will let `matchadd()` choose a random match id. If highlight group is left as `_`, this plugin will choose a random one from its [predefined ones](https://github.com/tanloong/interlaced.nvim/blob/dev/lua/interlaced/colors.lua).
**:ItMatchAddVisual** ibidem but populates the pattern column with the visually selected text.
**:ItListHighlights** shows the predefined highlight groups of this plugin.
**:ItListMatches** opens the matches window. You can edit highlight groups or pattern there and press `<Enter>` to apply the change.
**:ItMatchToggle** turns on/off highlighting for the matches.

**:ItLoad**
**:ItDump**
