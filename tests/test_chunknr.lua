#!/usr/bin/env lua

-- Tests for the chunk-number virtual text (absolute/relative) and counted pair
-- navigation.

local init = require "interlaced"
local config = require "interlaced.config"
local rpst = require "interlaced.reposition"
local mt = require "interlaced.match"

---@param name string
---@param expected any
---@param got any
local function check(name, expected, got)
  assert(vim.deep_equal(expected, got),
    ("%s: expected\n%s\ngot\n%s"):format(name, vim.inspect(expected), vim.inspect(got)))
end

---@param lines string[]
---@return integer
local function with_lines(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

---@param buf integer
---@return table<integer, string> line number -> virtual chunk number
local function chunk_labels(buf)
  local labels = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, init._ns_id, 0, -1, { details = true })) do
    labels[mark[2] + 1] = mark[4].virt_text[1][1]:gsub("%s+$", "")
  end
  return labels
end

-- ---------------------------------------------------------------------------
-- absolute chunk numbers
-- ---------------------------------------------------------------------------

do
  vim.wo.number = true
  vim.wo.relativenumber = true
  local lines = {}
  for i = 1, 9 do lines[i] = "line " .. i end
  local buf = with_lines(lines)

  init.ShowChunkNr()
  check("chunk numbers default to absolute", {
    [3] = "1",
    [6] = "2",
    [9] = "3",
  }, chunk_labels(buf))
  check("showing chunk numbers disables the system number column", false, vim.wo.number)
  check("showing chunk numbers disables the system relativenumber column", false, vim.wo.relativenumber)

  -- the system option must not control the plugin labels
  vim.wo.relativenumber = true
  init.RefreshChunkNr()
  check("system relativenumber does not affect absolute chunk numbers", {
    [3] = "1",
    [6] = "2",
    [9] = "3",
  }, chunk_labels(buf))
  vim.wo.relativenumber = false

  init.ClearChunkNr()
end

-- ---------------------------------------------------------------------------
-- system line-number columns are disabled in every window showing the buffer
-- ---------------------------------------------------------------------------

do
  local lines = {}
  for i = 1, 9 do lines[i] = "line " .. i end
  with_lines(lines)
  vim.cmd "split"
  local win1 = vim.api.nvim_get_current_win()
  vim.cmd "wincmd p"
  local win2 = vim.api.nvim_get_current_win()
  for _, win in ipairs { win1, win2 } do
    vim.wo[win].number = true
    vim.wo[win].relativenumber = true
  end

  vim.api.nvim_set_current_win(win1)
  init.ShowChunkNr()
  check("showing chunk numbers disables system numbers in all windows", {
    false, false, false, false,
  }, {
    vim.wo[win1].number, vim.wo[win1].relativenumber,
    vim.wo[win2].number, vim.wo[win2].relativenumber,
  })

  init.ClearChunkNr()
  vim.cmd "wincmd p"
  init.ClearChunkNr()
  vim.cmd "only"
end

-- ---------------------------------------------------------------------------
-- relative chunk numbers
-- ---------------------------------------------------------------------------

do
  local lines = {}
  for i = 1, 24 do lines[i] = "line " .. i end

  local buf = with_lines(lines)
  vim.api.nvim_win_set_cursor(0, { 10, 0 }) -- chunk 4
  init.ShowChunkNr()
  vim.cmd "Interlaced toggle_chunk_number_relative"
  check("relative mode numbers the visible chunks around the cursor chunk", {
    [3] = "3",
    [6] = "2",
    [9] = "1",
    [12] = "4",
    [15] = "1",
    [18] = "2",
    [21] = "3",
  }, chunk_labels(buf))

  vim.api.nvim_win_set_cursor(0, { 16, 0 }) -- chunk 6
  init.RefreshChunkNr()
  check("the cursor chunk is absolute after moving", {
    [3] = "5",
    [6] = "4",
    [9] = "3",
    [12] = "2",
    [15] = "1",
    [18] = "6",
    [21] = "1",
  }, chunk_labels(buf))

  -- the system option must not control the plugin labels
  vim.wo.relativenumber = true
  init.RefreshChunkNr()
  check("system relativenumber does not affect relative chunk numbers", {
    [3] = "5",
    [6] = "4",
    [9] = "3",
    [12] = "2",
    [15] = "1",
    [18] = "6",
    [21] = "1",
  }, chunk_labels(buf))
  vim.wo.relativenumber = false

  vim.cmd "Interlaced toggle_chunk_number_relative"
  check("toggling relative off restores absolute numbers", {
    [3] = "1",
    [6] = "2",
    [9] = "3",
    [12] = "4",
    [15] = "5",
    [18] = "6",
    [21] = "7",
    [24] = "8",
  }, chunk_labels(buf))

  vim.cmd "Interlaced toggle_chunk_number_relative"
  check("toggling relative back on uses relative numbers again", {
    [3] = "5",
    [6] = "4",
    [9] = "3",
    [12] = "2",
    [15] = "1",
    [18] = "6",
    [21] = "1",
  }, chunk_labels(buf))

  init.ClearChunkNr()
  init.ShowChunkNr()
  check("the relative mode survives hiding and showing", {
    [3] = "5",
    [6] = "4",
    [9] = "3",
    [12] = "2",
    [15] = "1",
    [18] = "6",
    [21] = "1",
  }, chunk_labels(buf))

  init.ClearChunkNr()
  vim.cmd "Interlaced toggle_chunk_number_relative"
  check("toggling relative while hidden updates the mode", false, init._chunknr_relative)
end

-- ---------------------------------------------------------------------------
-- the relative toggle applies to every buffer showing chunk numbers
-- ---------------------------------------------------------------------------

do
  local lines = {}
  for i = 1, 9 do lines[i] = "line " .. i end

  local buf_a = with_lines(lines)
  vim.api.nvim_win_set_cursor(0, { 4, 0 }) -- chunk 2
  init.ShowChunkNr()

  vim.cmd "vsplit"
  local buf_b = with_lines(lines)
  vim.api.nvim_win_set_cursor(0, { 4, 0 }) -- chunk 2
  init.ShowChunkNr()

  local expected_relative = { [3] = "1", [6] = "2", [9] = "1" }
  vim.cmd "Interlaced toggle_chunk_number_relative"
  check("the relative toggle updates the first buffer", expected_relative, chunk_labels(buf_a))
  check("the relative toggle updates the second buffer", expected_relative, chunk_labels(buf_b))

  local expected_absolute = { [3] = "1", [6] = "2", [9] = "3" }
  vim.cmd "Interlaced toggle_chunk_number_relative"
  check("toggling absolute updates the first buffer", expected_absolute, chunk_labels(buf_a))
  check("toggling absolute updates the second buffer", expected_absolute, chunk_labels(buf_b))

  init.ClearChunkNr()
  vim.cmd "wincmd p"
  init.ClearChunkNr()
  vim.cmd "only"
end

-- ---------------------------------------------------------------------------
-- counted navigation
-- ---------------------------------------------------------------------------

do
  config.lang_num = 2
  rpst.config.lang_num = 2

  local buf = with_lines {
    "foo foo", "foo foo", "", -- chunk 1, aligned
    "foo", "foo", "",         -- chunk 2, aligned
    "foo foo", "", "",        -- chunk 3, unaligned
    "foo", "foo", "",         -- chunk 4, aligned
    "foo", "", "",            -- chunk 5, unaligned
    "foo foo", "", "",        -- chunk 6, unaligned
  }
  mt._matches = { ["foo"] = { group = "ItColor1", id = 1, priority = 10 } }

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  rpst.action.navigate_down { count = 2 }
  check("navigate_down accepts a command count", 7, vim.fn.line ".")
  rpst.action.navigate_up { count = 1 }
  check("navigate_up accepts a command count", 4, vim.fn.line ".")
  rpst.action.navigate_down { fargs = { "3" } }
  check("navigate_down accepts a count argument", 13, vim.fn.line ".")

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd "Interlaced navigate_down 2"
  check("the :Interlaced command accepts a count", 7, vim.fn.line ".")

  vim.keymap.set("n", "J", function() rpst.action.navigate_down() end, { buffer = true })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys("2J", "x", false)
  check("navigate_down uses the keymap count", 7, vim.fn.line ".")
  vim.keymap.del("n", "J", { buffer = true })

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  rpst.action.next_unaligned { count = 1 }
  check("next_unaligned moves to the first unaligned chunk", 7, vim.fn.line ".")

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  rpst.action.next_unaligned { count = 2 }
  check("next_unaligned skips one unaligned chunk", 13, vim.fn.line ".")

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  rpst.action.next_unaligned { fargs = { "2" } }
  check("next_unaligned accepts a command count argument", 13, vim.fn.line ".")

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd "Interlaced next_unaligned 2"
  check("the :Interlaced command passes a count to next_unaligned", 13, vim.fn.line ".")

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  rpst.action.next_unaligned { count = 99 }
  check("next_unaligned stops at the last unaligned chunk", 16, vim.fn.line ".")

  vim.api.nvim_win_set_cursor(0, { 16, 0 })
  rpst.action.prev_unaligned { count = 1 }
  check("prev_unaligned moves to the nearest unaligned chunk above", 13, vim.fn.line ".")

  vim.api.nvim_win_set_cursor(0, { 16, 0 })
  rpst.action.prev_unaligned { count = 2 }
  check("prev_unaligned skips one unaligned chunk", 7, vim.fn.line ".")

  vim.api.nvim_win_set_cursor(0, { 16, 0 })
  rpst.action.next_unaligned {}
  check("next_unaligned stays put when nothing is found", 16, vim.fn.line ".")

  -- Starting inside a chunk, or on its separator, must still consider the
  -- adjacent chunk instead of skipping it.
  local buf2 = with_lines {
    "foo foo", "foo foo", "", -- chunk 1, aligned
    "foo", "", "",            -- chunk 2, unaligned
    "foo foo", "foo foo", "", -- chunk 3, aligned
  }
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  rpst.action.next_unaligned { count = 1 }
  check("next_unaligned from the middle of a chunk finds the adjacent chunk", 4, vim.fn.line ".")
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  rpst.action.next_unaligned { count = 1 }
  check("next_unaligned from a separator finds the adjacent chunk", 4, vim.fn.line ".")

  -- keep the buffers alive until the test ends
  check("navigation test buffers", true, vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_valid(buf2))
end

print "chunk numbers and counted navigation: ok"
