#!/usr/bin/env lua

-- Tests for `lua/interlaced/startlux.lua`: the window -> chunks scan, the
-- request it builds for POST /v1/decisions, and the answer it accepts. The
-- HTTP call itself is not exercised: it needs a key and a network round trip.

local startlux = require "interlaced.startlux"
local H = startlux._H

---@param name string
---@param expected any
---@param got any
local function check(name, expected, got)
  assert(vim.deep_equal(expected, got),
    ("%s: expected\n%s\ngot\n%s"):format(name, vim.inspect(expected), vim.inspect(got)))
end

local function with_lines(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

-- ---------------------------------------------------------------------------
-- chunks
-- ---------------------------------------------------------------------------

do
  with_lines {
    "“我告诉你，菲龙会带来危险。”", -- 1
    "“You don’t know that.", -- 2
    "", -- 3
    "“你怎么知道这点？”", -- 4
    "“How do you know this?”", -- 5
    "", -- 6
    "单独一行", -- 7
  }

  local blocks = H.blocks(1, 7)
  check("one block per chunk", 3, #blocks)
  check("first block", { start = 1, stop = 2 }, { start = blocks[1].start, stop = blocks[1].stop })
  check("last block is a single line", { start = 7, stop = 7 }, { start = blocks[3].start, stop = blocks[3].stop })

  check("describe shows the line number and heads", true,
    H.describe(blocks[1]):find("^行1: ") ~= nil)
end

-- ---------------------------------------------------------------------------
-- request
-- ---------------------------------------------------------------------------

do
  with_lines {
    "裴洛拉特在驾驶舱门口停下脚步，带着几分不安的神情向内探望，像是想判断崔维兹是否在专心工作。",
    "Pelorat paused at the door to the pilot-room and looked inside in a rather ill-at-ease manner.",
    "",
    "崔维兹双手一直放在桌面上；当他成为电脑的一部分时，总是双眼凝视显像荧幕，维持着这种姿势。",
    "It was as though he were trying to decide whether Trevize was hard at work or not.",
  }

  local body = H.build_payload(1, 5)
  local data = vim.json.decode(body)
  check("one question only", { "first_unpair" }, vim.tbl_keys(data.questions))
  check("choice question", "choice", data.questions.first_unpair.type)
  check("one option per chunk plus none", 3, #vim.tbl_keys(data.questions.first_unpair.criteria))
  check("absolute line numbers in state", true, data.state:find("1|裴洛拉特", 1, true) ~= nil)
  check("only the first line is asked about", true,
    data.questions.first_unpair.instructions:find("第一个", 1, true) ~= nil)
end

-- ---------------------------------------------------------------------------
-- answers
-- ---------------------------------------------------------------------------

do
  local lnum, err = H.parse_answer '{"answers":{"first_unpair":{"choice":"82339"}}}'
  check("line number answer", 82339, lnum)
  check("no error", nil, err)

  lnum = H.parse_answer '{"answers":{"first_unpair":{"choice":"none"}}}'
  check("none answer", "none", lnum)

  lnum = H.parse_answer '{"answers":{"first_unpair":{"choice":null}}}'
  check("null answer means none", "none", lnum)

  lnum, err = H.parse_answer '{"error":{"message":"bad key"}}'
  check("api error", nil, lnum)
  check("api error text", "bad key", err)

  lnum, err = H.parse_answer "<html>gateway</html>"
  check("non-json", nil, lnum)
  check("non-json is reported", true, err:find("JSON", 1, true) ~= nil)
end

-- ---------------------------------------------------------------------------
-- jump target
-- ---------------------------------------------------------------------------

do
  local blocks = { { start = 10, stop = 11 }, { start = 13, stop = 14 } }
  check("line inside a chunk", { start = 13, stop = 14 }, H.block_at(13, blocks, 10, 14))
  check("line at the end of a chunk", { start = 10, stop = 11 }, H.block_at(11, blocks, 10, 14))
  check("window-relative line is rebased", { start = 13, stop = 14 }, H.block_at(4, blocks, 10, 14))
  check("line past the window lands on the last chunk", { start = 13, stop = 14 }, H.block_at(99, blocks, 10, 14))
end

print "startlux: ok"
