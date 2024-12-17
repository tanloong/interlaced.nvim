# interlaced.nvim

Text re-positioning for bilingual sentence alignment.

## Requirements

+ Neovim >= **0.9.0**

## Installation

+ Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "tanloong/interlaced.nvim",
  config = function() require("interlaced").setup {} end,
  ft = "text",
}
```

## Configuration

https://github.com/tanloong/interlaced.nvim/blob/20d0ff5cbd40361b50a9e8f02938f29b9326d025/lua/interlaced/config.lua#L1-L66

## Commands

**:ItEnableKeybindings** applies keybindings specified in the `mappings` field of the table passed to `require("interlaced").setup()`. Original keymaps are backed up.

**:ItDisableKeybindings** cancels `mappings` keybindings and restores backed up keymaps.

**:ItSplitEnglishSentences** identifies English sentence endings and insert a newline after each of them. Works linewise on the range when provided, the whole buffer if not.

**:ItSplitChineseSentences** ibidem but identifies Chinese sentence endings.

**:ItInterlaceWithL1 {filepath}** mixes non-empty lines from current buffer with those from `filepath` into empty-line-separated pairs of lines. In each pair, lines from `filepath` are above those from current buffer. `mappings` keybindings are enabled if they have not been previously.

**:ItInterlaceWithL2 {filepath}** ibidem but lines from `filepath` are below those from current buffer.

**:[range]ItInterlace [num]** mixes non-empty lines from current buffer into `num` empty-line-separated groups. If `num` is not provided, `lang_num` field of the config table will be used. Works on the range when provided, the whole buffer if not.

**:ItDeinterlace**

**:ItMatchAdd** opens a matches window to edit a pattern to be highlighted. The window has 3 columns: match id, highlight group, and pattern. On pressing `<Enter>` in insert/normal mode, `matchadd()` will be called with the 3 values (see `:h matchadd()`). If match id is left as `_`, a random one will be chosen by `matchadd()` . If highlight group is left as `_`, a random one will be chosen from the plugin's [predefined ones](https://github.com/tanloong/interlaced.nvim/blob/dev/lua/interlaced/colors.lua).

**:ItMatchAddVisual** ibidem but populates the pattern column with the visually selected text.

**:ItListMatches** opens the matches window. You can edit highlight groups or pattern there and press `<Enter>` to apply the change.

**:ItClearMatches** removes all matches. This action cannot be undone.

**:ItMatchToggle** turns on/off highlighting for the matches.

**:ItListHighlights** shows the predefined highlight groups of this plugin.

**:ItSwapWithAbove** swaps current line with the counterpart line from the chunk above.

**:ItSwapWithBelow** ibidem but from the chunk below.

**:ItPushUp** appends current line up to the end of its counterpart at the chunk above. Subsequent counterpart lines are moved up correspondingly.

**:ItPushUpPair** ibidem but works every line in the current chunk.

**:ItPullBelow** applies **ItPushUp** on the counterpart of the current line at the chunk below.

**:ItPullBelowPair** ibidem but on every line in the current below.

**:ItPushDownRightPart** moves the text from the cursor position to the end of the current line down to its counterpart line at the chunk below. Subsequent counterpart lines are moved down correspondingly. The current line is left with the text leftside of the cursor.

**:ItPushDown** ibidem but works on the whole current line. The current line is left as empty.

**:ItLeaveAlone** pushes down all lines (except the cursor line) in the current chunk, puts a `-` as placeholder at each, and moves cursor down to the next chunk.

**:ItNextUnaligned** finds the next chunk has different kinds of highlighted matches across its lines and puts cursor there.

**:ItPrevUnaligned** ibidem but finds the previous chunk.

**:ItSetLangNum {num}** changes language number, i.e., how many lines should be in each chunk. This affects re-positioning actions: `ItPushUp(Pair)`, `ItPullBelow(Pair)`, `ItPushDown(RightPart)`, `ItSwapWithAbove`, `ItSwapWithBelow`, and `ItLeaveAlone`. When called without argument or with a single `?` it shows the current value.

**:ItSetSeparator {num} {str}** changes sentence separator to `str` for the `num`th language, i.e., what should be inserted between on `ItPushUp(Pair)` and `ItPullBelow(Pair)`. When called without argument or with a single `?` it shows current values. 

**:ItNavigateDown** moves cursor down by `language number + 1` lines.

**:ItNavigateUp** moves cursor up by `language number + 1` lines.

**:ItUndo** undoes the last re-positioning action. The undo list remembers at most 100 actions and forgets oldest ones thereafter.

**:ItRedo** undoes the last `ItUnDo`.

**:ItDump [filepath]** saves workspace to `filepath`: cursor position, matches, language separator, and language number. Undo and redo lists are not saved. Uses `./.interlaced.json` when called without argument.

**:ItLoad [filepath]** loads workspace from `filepath`. Uses `./.interlaced.json` when called without argument.
