# interlaced.nvim

Text re-positioning for bilingual sentence alignment.

## Requirements

+ Neovim >= **0.9.0**

## Installation

+ Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "tanloong/interlaced.nvim",
  config = function() require("interlaced") end,
  ft = "text",
}
```

## Configuration

Use `vim.g.interlaced` option table and modifiy the field what you need before the plugin is loaded.

```lua
vim.g.interlaced = {
  keymaps = {
    { "n", ",", "push_up"},
    { "n", "<", "push_up_pair"},
    { "n", "e", "push_up_left_part"},
    { "n", ".", "pull_below"},
    { "n", ">", "pull_below_pair"},
    { "n", "d", "push_down_right_part"},
    { "n", "D", "push_down"},
    { "n", "s", "leave_alone"},
    { "n", "[e", "swap_with_above"},
    { "n", "]e", "swap_with_below"},
    { "n", "U", "undo"},
    { "n", "R", "redo"},
    { "n", "J", "navigate_down"},
    { "n", "K", "navigate_up"},
    { "n", "md", "dump"},
    { "n", "ml", "load"},
    { "n", "gn", "next_unaligned"},
    { "n", "gN", "prev_unaligned"},
    { "n", "mt", "match_toggle"},
    { "n", "m;", "list_matches"},
    { "n", "ma", "match_add"},
    { "v", "ma", "match_add_visual"},
  },
  setup_mappings_now = false,
  separators = { ["1"] = "", ["2"] = " " },
  lang_num = 2,
  enable_keybindings_hook = function()
    -- disable coc to avoid lag on :w
    if vim.g.did_coc_loaded ~= nil then vim.cmd [[CocDisable]] end
    -- disable the undo history saving, which is time-consuming and causes lag
    vim.opt_local.undofile = false
    -- pcall(vim.cmd.nunmap, "j")
    -- pcall(vim.cmd.nunmap, "k")
    -- pcall(vim.cmd.nunmap, "gj")
    -- pcall(vim.cmd.nunmap, "gk")
    -- vim.opt_local.undolevels = -1
    vim.opt_local.signcolumn = "no"
    vim.opt_local.relativenumber = false
    vim.opt_local.number = false
    require "interlaced".action.load()
    require "interlaced".ShowChunkNr()
  end,
  sound_feedback = false,
}
```

## Commands

| command | description |
| - | - |
| **:Interlaced enable_keybindings**  | applies keybindings specified in the `keymaps` field in `vim.g.interlaced`. Original keymaps are backed up. |
| **:Interlaced disable_keybindings**  | cancels `keymaps` keybindings and restores backed up keymaps. |
| **:Interlaced split_english_sentences**  | identifies English sentence endings and insert a newline after each of them. Works linewise on the range when provided, the whole buffer if not. |
| **:Interlaced split_chinese_sentences**  | ibidem but identifies Chinese sentence endings. |
| **:Interlaced interlace_with_l1 {filepath}**  | mixes non-empty lines from current buffer with those from `filepath` into empty-line-separated pairs of lines. In each pair, lines from `filepath` are above those from current buffer. `keymaps` keybindings are enabled if they have not been previously. |
| **:Interlaced interlace_with_l2 {filepath}**  | ibidem but lines from `filepath` are below those from current buffer. |
| **:[range]Interlaced interlace [num]**  | mixes non-empty lines from current buffer into `num` empty-line-separated chunks. Works on the range when provided, the whole buffer if not. If `num` is not provided, `lang_num` field of the `vim.g.interlaced` will be used. |
| **:[range]Interlaced deinterlace [num]**  | Works on the range when provided, the whole buffer if not. If `num` is not provided, `lang_num` field of the `vim.g.interlaced` will be used. |
| **:Interlaced match_add**  | opens a matches window to edit a pattern to be highlighted. The window has 3 columns: match id, highlight group, and pattern. On pressing `<Enter>` in insert/normal mode, `matchadd()` will be called with the 3 values (see `:h matchadd()`). If match id is left as `_`, a random one will be chosen by `matchadd()` . If highlight group is left as `_`, a random one will be chosen from the plugin's [predefined ones](https://github.com/tanloong/interlaced.nvim/blob/dev/lua/interlaced/colors.lua). In normal mode, `D` deletes match of current line, `U` undoes the deletion, `R` switches a random color for the match under the cursor. |
| **:Interlaced match_add_visual**  | ibidem but populates the pattern column with the visually selected text. |
| **:Interlaced list_matches**  | opens the matches window. You can edit highlight groups or pattern there and press `<Enter>` to apply the change. |
| **:Interlaced clear_matches**  | removes all matches. This action cannot be undone. |
| **:Interlaced match_toggle**  | turns on/off highlighting for the matches. |
| **:Interlaced list_highlights**  | shows the predefined highlight groups of this plugin. |
| **:Interlaced swap_with_above**  | swaps current line with the counterpart line from the chunk above. |
| **:Interlaced swap_with_below**  | ibidem but from the chunk below. |
| **:Interlaced push_up [lineno]**  | appends the line at `lineno` up to the end of its counterpart at the chunk above. Subsequent counterpart lines are moved up correspondingly. Works on the current line if `lineno` is not provided. |
| **:Interlaced push_up_pair [lineno]**  | ibidem but works on every line in the chunk where `lineno` is at. |
| **:Interlaced push_up_left_part [lineno [colno]]**  | appends the text leftside of column `colno` at line `lineno` up to its counterpart in the chunk above, leaving line `lineno` with the text rightside of column `colno`. Works on the current line if `lineno` is not provided. Uses cursor position if `colno` is not provided. |
| **:Interlaced pull_below [lineno]**  | appends the counterpart at the chunk below to line `lineno`. Subsequent counterpart lines are moved up correspondingly. Works on the current line if `lineno` is not provided. |
| **:Interlaced pull_below_pair [lineno]**  | ibidem but works on every line in the chunk where `lineno` is at. |
| **:Interlaced push_down_right_part [lineno [colno]]**  | moves the text rightside of column `colno` at line `lineno` down to its counterpart at the chunk below, leaving lineno `lineno` with the text leftside of column `colno`. Subsequent counterpart lines are moved down correspondingly. Works on the current line if `lineno` is not provided. Uses cursor position if `colno` is not provided. |
| **:Interlaced push_down [lineno]**  | ibidem but moves down the whole line `lineno`, leaving it as empty. |
| **:Interlaced leave_alone [lineno]**  | pushes down all lines (except the cursor line) in the chunk where `lineno` is at, puts a `-` as placeholder at each, and moves cursor down to the next chunk. Works on the cursor chunk if `lineno` is not provided. |
| **:Interlaced next_unaligned**  | moves cursor down to the chunk that has different kinds of highlighted matches across its lines. |
| **:Interlaced prev_unaligned**  | ibidem but moves cursor up. |
| **:Interlaced set_lang_num {num}**  | changes `lang_num`, i.e., how many lines should be in each chunk. This affects re-positioning actions (`Interlaced push_up(_pair)`, `Interlaced pull_below(_pair)`, `Interlaced push_down(_right_part)`, and `Interlaced leave_alone`). When called without argument or with a single `?` it shows the current value. |
| **:Interlaced set_separator {num} {str}**  | changes sentence separator to `str` for the `num`th language, i.e., what should be inserted between on `ItPushUp(Pair|LeftPart)?` and `ItPullBelow(Pair)?`. When called without argument or with a single `?` it shows current values.  |
| **:Interlaced navigate_down**  | moves cursor down by `lang_num + 1` lines. |
| **:Interlaced navigate_up**  | moves cursor up by `lang_num + 1` lines. |
| **:Interlaced undo**  | undoes the last re-positioning action. The undo list remembers at most 100 re-positionings and forgets oldest ones thereafter. It costs too much RAM to remember changes of an interlaced buffer, because re-positioning affects every counterpart line from the cursor below, and the builtin *undo history* stores all of that. One `Interlaced push_up` at the beginning of an interlaced buffer with 190k lines increases memory use by 100M. To avoid memory creep, the plugin has an isolated *operation history* for re-positioning operations (`Interlaced push_up(_pair)`, `Interlaced pull_below(_pair)`, `Interlaced push_down(_right_part)`, and `Interlaced leave_alone`). It disables the builtin *undo history* recording before a re-positioning operation is called, appends the operation to its *operation history*, and enables the *undo history* afterwards. Note that the builtin *undo history* is cleared every time an re-positioning operation is called. Use `:Interlaced undo` to undo a re-positioning operation. Use the traditional `u` to undo normal text changes like inserting, pasting, etc. |
| **:Interlaced redo**  | undoes the last `Interlaced undo`. |
| **:Interlaced toggle_chunk_number**  | shows/hides chunk number at intervals. |
| **:Interlaced dump [filepath]**  | saves workspace to `filepath`: cursor position, matches, language separator, and `lang_num`. Undo and redo lists are not saved. Uses `./.interlaced.json` when called without argument. |
| **:Interlaced load [filepath]**  | loads workspace from `filepath`. Uses `./.interlaced.json` when called without argument. |
