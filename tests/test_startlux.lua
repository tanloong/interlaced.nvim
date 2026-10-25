#!/usr/bin/env lua

-- Tests for `lua/interlaced/startlux.lua`: the window -> chunks scan, the
-- first-unpair and operation requests it builds for POST /v1/decisions, and the
-- answers it accepts. The HTTP call itself is not exercised: it needs a key and
-- a network round trip.

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

do
  with_lines {
    "第一块中文", -- 1
    "first english", -- 2
    "", -- 3
    "第二块中文", -- 4
    "second english", -- 5
    "", -- 6
    "第三块中文", -- 7
    "third english", -- 8
  }

  local complete = H.complete_blocks(2, 8)
  check("a window beginning inside a chunk drops that chunk", 2, #complete)
  check("the first complete chunk after the cut", { start = 4, stop = 5 },
    { start = complete[1].start, stop = complete[1].stop })

  complete = H.complete_blocks(1, 7)
  check("a window ending inside a chunk drops that chunk", 2, #complete)
  check("the last complete chunk before the cut", { start = 4, stop = 5 },
    { start = complete[2].start, stop = complete[2].stop })

  local data = vim.json.decode(H.build_payload(1, 7))
  check("a truncated chunk is not an option", nil, data.questions.first_unpair.criteria["7"])
  check("complete chunks plus none are options", 3,
    #vim.tbl_keys(data.questions.first_unpair.criteria))
  check("the state warns about truncated edges", true,
    data.state:find("不完整", 1, true) ~= nil)
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
-- operation decision
-- ---------------------------------------------------------------------------

do
  with_lines {
    "第一块中文", -- 1
    "first english", -- 2
    "", -- 3
    "第二块中文", -- 4
    "second english", -- 5
    "", -- 6
    "第三块中文", -- 7
    "third english", -- 8
    "", -- 9
    "第四块中文", -- 10
    "fourth english", -- 11
  }

  local blocks = H.blocks(1, 11)
  local cur, prev, nxt = blocks[3], blocks[2], blocks[4]
  check("line 7 is Chinese", "中文", H.line_tag(7))
  check("line 8 is English", "英文", H.line_tag(8))
  check("line 9 is a separator", nil, H.line_role(9))
  check("previous block", { start = 4, stop = 5 }, { start = H.block_before(cur).start, stop = H.block_before(cur).stop })
  check("next block", { start = 10, stop = 11 }, { start = H.block_after(cur).start, stop = H.block_after(cur).stop })

  local options = H.operation_options(cur, prev, nxt)
  for _, key in ipairs {
    "push_up:7", "push_up:8", "push_up_pair:7",
    "pull_below:7", "pull_below:8", "pull_below_pair:7",
    "push_down:7", "push_down:8", "push_down:5",
    "push_up_left_part:7", "push_up_left_part:8",
    "push_down_right_part:7", "push_down_right_part:8",
    "push_up_left_part:10", "push_up_left_part:11",
    "push_down_right_part:5",
    "leave_alone:7", "leave_alone:8", "none",
  } do
    check("operation option " .. key, true, options[key] ~= nil)
  end
  check("the first chunk cannot push up", nil, options["push_up:1"])
  check("the first chunk cannot push up a part", nil, options["push_up_left_part:1"])
  check("the last chunk cannot push down a part", nil, options["push_down_right_part:10"])

  local body, built = H.build_operation_payload(cur, prev, nxt)
  local data = vim.json.decode(body)
  check("one operation question", { "operation" }, vim.tbl_keys(data.questions))
  check("operation is a choice", "choice", data.questions.operation.type)
  check("same criteria in payload", options, data.questions.operation.criteria)
  check("state labels the current block", true, data.state:find("7|中文|第三块中文", 1, true) ~= nil)
  check("state includes the previous block", true, data.state:find("5|英文|second english", 1, true) ~= nil)
  check("state includes the next block", true, data.state:find("10|中文|第四块中文", 1, true) ~= nil)
  check("criteria description names the target line", true,
    built["push_down:5"]:find("行5", 1, true) ~= nil)

  local answer, err = H.parse_operation(
    '{"answers":{"operation":{"choice":"push_down:5","confidence":0.81}}}', options)
  check("operation answer", "push_down", answer.op)
  check("operation target line", 5, answer.lnum)
  check("operation confidence", 0.81, answer.confidence)
  check("no operation error", nil, err)

  answer = H.parse_operation('{"answers":{"operation":{"choice":"none"}}}', options)
  check("none operation", "none", answer.op)

  answer, err = H.parse_operation(
    '{"answers":{"operation":{"choice":"push_down_right_part:7","confidence":0.66}}}', options)
  check("inline operation name", "push_down_right_part", answer.op)
  check("inline operation target line", 7, answer.lnum)
  check("inline operation confidence", 0.66, answer.confidence)
  check("no inline operation error", nil, err)
  check("inline operations are partial", true, H.is_partial("push_up_left_part"))
  check("whole-line operations are not partial", false, H.is_partial("push_down"))

  answer, err = H.parse_operation('{"answers":{"operation":{"choice":"push_down:999"}}}', options)
  check("unknown operation is rejected", nil, answer)
  check("unknown operation is reported", true, err:find("unreadable", 1, true) ~= nil)

  answer, err = H.parse_operation('{"answers":{"operation":{"choice":null}}}', options)
  check("null operation is rejected", nil, answer)
  check("null operation is reported", true, err:find("no operation", 1, true) ~= nil)

  check("startlux_op action exists", "function", type(startlux.action.startlux_op))
end

-- ---------------------------------------------------------------------------
-- inline split points
-- ---------------------------------------------------------------------------

do
  with_lines {
    "第二块中文；第二块后半句。", -- 1
    "It was as though he were trying", -- 2
    "", -- 3
    "下一块中文", -- 4
    "next english", -- 5
  }

  local chars, cols = H.char_cols("a中b")
  check("characters of a mixed line", { "a", "中", "b" }, chars)
  check("byte columns of a mixed line", { 1, 2, 5, 6 }, cols)

  local candidates = H.split_candidates(1)
  local by_col = {}
  for _, candidate in ipairs(candidates) do by_col[candidate.col] = candidate end
  check("the Chinese semicolon is a split point", true, by_col[19] ~= nil)
  check("left side of the semicolon split", "第二块中文；", by_col[19] and by_col[19].left or nil)
  check("right side of the semicolon split", "第二块后半句。", by_col[19] and by_col[19].right or nil)
  for _, candidate in ipairs(candidates) do
    check("split " .. candidate.col .. " has a non-empty left side", true, candidate.left ~= "")
    check("split " .. candidate.col .. " has a non-empty right side", true, candidate.right ~= "")
  end

  local line = vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]
  local english = H.split_candidates(2)
  check("the English line has split points", true, #english > 0)
  for _, candidate in ipairs(english) do
    check("English split " .. candidate.col .. " is a word start", " ", line:sub(candidate.col - 1, candidate.col - 1))
  end

  local split_options = H.split_options(candidates)
  check("one option per split point plus none", #candidates + 1, vim.tbl_count(split_options))
  check("none split option", true, split_options.none ~= nil)
  check("split option names its byte column", true, split_options["col:19"]:find("第19字节", 1, true) ~= nil)
  check("split option shows the left side", true, split_options["col:19"]:find("第二块中文", 1, true) ~= nil)
  check("split option shows the right side", true, split_options["col:19"]:find("第二块后半句。", 1, true) ~= nil)
end

do
  with_lines { "中文", "Version 3.14 works." }

  local cols = {}
  for _, candidate in ipairs(H.split_candidates(2)) do cols[candidate.col] = true end
  check("an English split starts a word", true, cols[9] ~= nil)
  check("the next English word is a split", true, cols[14] ~= nil)
  check("a decimal point is not a split", nil, cols[11])
end

do
  with_lines { "甲乙丙丁，戊己庚辛，壬癸。" }

  local saved = startlux.config.split_max_options
  startlux.config.split_max_options = 4
  local candidates = H.split_candidates(1)
  startlux.config.split_max_options = saved

  check("split candidates are capped", 4, #candidates)
  local has_punctuation_split = false
  for _, candidate in ipairs(candidates) do
    if candidate.col == 16 then has_punctuation_split = true end
  end
  check("punctuation splits survive the cap", true, has_punctuation_split)
end

do
  with_lines {
    "第一块中文", -- 1
    "first english", -- 2
    "", -- 3
    "第二块中文；第二块后半句。", -- 4
    "second english that continues", -- 5
    "", -- 6
    "第三块中文", -- 7
    "third english", -- 8
  }

  local blocks = H.blocks(1, 8)
  local cur, prev, nxt = blocks[2], blocks[1], blocks[3]
  local body, options = H.build_split_payload(cur, prev, nxt, {
    op = "push_down_right_part",
    lnum = 4,
  })
  check("split payload exists", true, body ~= nil)

  local data = vim.json.decode(body)
  check("one split question", { "split" }, vim.tbl_keys(data.questions))
  check("split is a choice", "choice", data.questions.split.type)
  check("split payload uses the candidates", options, data.questions.split.criteria)
  check("split state names the operation", true, data.state:find("push_down_right_part", 1, true) ~= nil)
  check("split state shows the target line", true, data.state:find("4|中文|第二块中文；第二块后半句。", 1, true) ~= nil)
  check("split state also asks for none", true, data.state:find("none", 1, true) ~= nil)

  local split, err = H.parse_split(
    '{"answers":{"split":{"choice":"col:19","confidence":0.7}}}', options)
  check("split answer key", "col:19", split.key)
  check("split answer column", 19, split.col)
  check("split answer confidence", 0.7, split.confidence)
  check("no split error", nil, err)

  split = H.parse_split('{"answers":{"split":{"choice":"none"}}}', options)
  check("none split", "none", split.key)

  split, err = H.parse_split('{"answers":{"split":{"choice":"col:999"}}}', options)
  check("unknown split is rejected", nil, split)
  check("unknown split is reported", true, err:find("unreadable", 1, true) ~= nil)

  split, err = H.parse_split('{"answers":{"split":{"choice":null}}}', options)
  check("null split is rejected", nil, split)
  check("null split is reported", true, err:find("no split", 1, true) ~= nil)

  split, err = H.parse_split("<html>gateway</html>", options)
  check("non-json split is rejected", nil, split)
  check("non-json split is reported", true, err:find("JSON", 1, true) ~= nil)
end

-- ---------------------------------------------------------------------------
-- applying an operation
-- ---------------------------------------------------------------------------

do
  with_lines {
    "第一块中文", -- 1
    "first english", -- 2
    "", -- 3
    "第二块中文", -- 4
    "second english", -- 5
    "", -- 6
    "第三块中文", -- 7
    "third english", -- 8
  }

  local ok, err = H.apply_operation { op = "push_up_pair", lnum = 4 }
  check("pair operation applied", true, ok)
  check("no apply error", nil, err)
  check("pair joined above", {
    "第一块中文第二块中文",
    "first english second english",
    "",
    "第三块中文",
    "third english",
  }, vim.api.nvim_buf_get_lines(0, 0, -1, false))

  ok, err = H.apply_operation { op = "push_up_pair", lnum = 1 }
  check("no-op operation is rejected", false, ok)
  check("no-op operation is reported", true, err:find("made no change", 1, true) ~= nil)

  ok, err = H.apply_operation { op = "none", lnum = 1 }
  check("none is not applied", false, ok)
  check("none is reported", true, err:find("unknown operation", 1, true) ~= nil)

  check("startlux_apply action exists", "function", type(startlux.action.startlux_apply))
end

do
  local lines = {
    "第一块中文", -- 1
    "first english", -- 2
    "", -- 3
    "第二块中文", -- 4
    "second english", -- 5
    "", -- 6
    "第三块中文", -- 7
    "third english", -- 8
  }
  with_lines(lines)

  local ok, err = H.apply_operation { op = "push_up_left_part", lnum = 4, cnum = 10 }
  check("inline push up applied", true, ok)
  check("no inline push up error", nil, err)
  check("left part joined above", {
    "第一块中文第二块",
    "first english",
    "",
    "中文",
    "second english",
    "",
    "第三块中文",
    "third english",
  }, vim.api.nvim_buf_get_lines(0, 0, -1, false))

  ok, err = H.apply_operation { op = "push_down_right_part", lnum = 4 }
  check("inline operation needs a split column", false, ok)
  check("missing split column is reported", true, err:find("split column", 1, true) ~= nil)
end

do
  with_lines {
    "第一块中文", -- 1
    "first english", -- 2
    "", -- 3
    "第二块中文", -- 4
    "second english", -- 5
    "", -- 6
    "第三块中文", -- 7
    "third english", -- 8
  }

  local ok, err = H.apply_operation { op = "push_down_right_part", lnum = 4, cnum = 10 }
  check("inline push down applied", true, ok)
  check("no inline push down error", nil, err)
  check("right part moved to the next counterpart", {
    "第一块中文",
    "first english",
    "",
    "第二块",
    "second english",
    "",
    "中文",
    "third english",
    "",
    "第三块中文",
  }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
end

do
  local lines = {}
  for i = 1, 200 do lines[i] = "line " .. i end
  with_lines(lines)

  local before = vim.fn.line("w0")
  check("page down reports movement", true, H.page_down())
  check("page down advances the window", true, vim.fn.line("w0") > before)
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
