#!/usr/bin/env lua

-- Regression tests for the chunk layout produced by `:Interlaced interlace` and
-- consumed by `:Interlaced deinterlace`, and for range handling of the
-- sentence-splitting commands.

local rpst = require "interlaced.reposition"
local config = require "interlaced.config"

---@param lines string[]
---@param k integer
---@return string[]
local function interlace_then_deinterlace(lines, k)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  rpst.action.interlace { line1 = 1, line2 = vim.fn.line "$", fargs = { tostring(k) } }
  rpst.action.deinterlace { line1 = 1, line2 = vim.fn.line "$", fargs = {} }
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

---@param name string
---@param got string[]
---@param expected string[]
local function check(name, got, expected)
  assert(#got == #expected,
    ("%s: expected %d lines, got %d"):format(name, #expected, #got))
  for i, line in ipairs(expected) do
    assert(got[i] == line,
      ("%s: line %d expected %q, got %q"):format(name, i, line, got[i]))
  end
end

-- Equal-length language blocks are gathered back into per-language groups.
check("even k2", interlace_then_deinterlace({ "a1", "a2", "b1", "b2" }, 2),
  { "a1", "a2", "", "b1", "b2" })
check("even k3", interlace_then_deinterlace({ "a1", "a2", "b1", "b2", "c1", "c2" }, 3),
  { "a1", "a2", "", "b1", "b2", "", "c1", "c2" })

-- Leftover lines fill the extra slot of the last language(s) instead of being
-- appended raw, so they stay aligned with the chunk stride.
check("remainder k3", interlace_then_deinterlace({ "a1", "a2", "b1", "b2", "c1", "c2", "x" }, 3),
  { "a1", "a2", "", "b1", "b2", "", "c1", "c2", "x" })
check("remainder k2", interlace_then_deinterlace({ "a1", "a2", "b1", "b2", "x" }, 2),
  { "a1", "a2", "", "b1", "b2", "x" })

-- `interlace` must persist `lang_num`, otherwise a following `deinterlace`
-- would use a stale chunk size and scramble the buffer.
config.lang_num = 2
interlace_then_deinterlace({ "a1", "a2", "b1", "b2", "c1", "c2" }, 3)
assert(config.lang_num == 3, "interlace should persist lang_num, got " .. tostring(config.lang_num))
assert(rpst.config.lang_num == 3, "reposition must observe the same lang_num")

-- `split_*_sentences` must keep the lines outside the given range.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "keep1", "a. b.", "keep2" })
rpst.action.split_english_sentences { line1 = 2, line2 = 2 }
local out = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(out[1] == "keep1", "split must not touch lines above the range")
assert(out[#out] == "keep2", "split must not touch lines below the range")
assert(#out > 3, "split should have produced new lines inside the range")

print "all interlace/deinterlace tests passed"
