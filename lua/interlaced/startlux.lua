---StartLux Decision client for interlaced.nvim.
---
---`:Interlaced startlux_op` looks at the window, asks the StartLux Decision API
---(POST `/v1/decisions`) for the **first unaligned pair**, then sends a focused
---request with the chunk before/at/after it. It suggests one whole-line/pair
---operation (`push_up`, `pull_below`, `push_down`, `push_up_pair`,
---`pull_below_pair`, `leave_alone`) or one inline operation
---(`push_up_left_part` / `push_down_right_part`). Inline operations get a third,
---tiny request that picks the split point, because only the line contents can
---tell where one sentence ends and the next begins.
---
---`startlux_op` only suggests: the cursor is moved to the target line/column
---and the pair flashes, but the buffer is not modified. `startlux_apply` runs
---the same requests and executes the suggestion; when the window has no unpair
---it scrolls one page forward with `<C-F>` instead.
---
---The first question is deliberately tiny: the payload contains the visible
---window with absolute line numbers, and the only question is "which chunk is
---the first one whose Chinese and English do not match". Because a misaligned
---chunk shifts every later chunk by one, the first mismatch is the only one
---worth locating.
---
---Options are read from `vim.g.interlaced.startlux` (or the flat
---`vim.g.interlaced_startlux`), falling back to `M.config` below.
---
---Subcommands (`init.lua` adds this module to the `:Interlaced` dispatcher and
---`config.keymaps` binds `gn` to `startlux_op`):
---  :Interlaced startlux_op       ask, then suggest an operation at the target line
---  :Interlaced startlux_apply    ask, then apply the suggested operation
---  :Interlaced startlux_cancel   drop the in-flight request
---  :Interlaced startlux_prompt   show the first-unpair request
---
---The locating and suggesting commands only read the window and nearby buffer
---lines and move the cursor; `startlux_apply` delegates the actual edit to
---`interlaced.reposition` so `:Interlaced undo` can revert it.

local M = {
  _H = {},
  action = {},
}

---Defaults, overridable via `vim.g.interlaced.startlux`.
M.config = {
  ---OpenAI-compatible base URL; `/decisions` is appended
  base_url = "https://api.bamboonode.dev/v1",
  model = "startlux-decision-27b-autothink",
  ---sent as `Authorization: Bearer <key>`; nil means "look it up" (see `key_file`)
  api_key = nil,
  ---`$BAMBOO_API_KEY`, `$STARTLUX_API_KEY`, `api_key`, then this file
  key_file = "~/.config/opencode/bamboo-api-key",
  ---"never" keeps the round trip short; "auto" lets the model think when unsure
  think_mode = "never",
  ---seconds curl may take for the whole request
  timeout_s = 20,
  curl = "curl",
  ---how long the pair stays highlighted, in milliseconds
  highlight_ms = 1200,
  ---highlight group used for the flashed lines
  highlight_group = "InterlacedUnpairFlash",
  ---how many chunks are offered as choices; longer windows are cut off
  max_options = 80,
  ---how many split points are offered for an inline operation
  split_max_options = 60,
}

local uv = vim.uv or vim.loop
local api = vim.api
local fn = vim.fn
local H = M._H

---In-flight request, or nil: `{ cancel = fun() }`.
M.pending = nil


-- ---------------------------------------------------------------------------
-- options
-- ---------------------------------------------------------------------------

---@param key string
---@return any
local function opt(key)
  local nested = vim.g.interlaced
  if type(nested) == "table" and type(nested.startlux) == "table" and nested.startlux[key] ~= nil then
    return nested.startlux[key]
  end
  local flat = vim.g.interlaced_startlux
  if type(flat) == "table" and flat[key] ~= nil then
    return flat[key]
  end
  return M.config[key]
end

M.opt = opt

---@param text string
---@return string
local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param text string
---@param width integer
---@return string
local function clip(text, width)
  if fn.strchars(text) <= width then return text end
  return fn.strcharpart(text, 0, width) .. "…"
end

-- ---------------------------------------------------------------------------
-- API key
-- ---------------------------------------------------------------------------

---@return string|nil
H.api_key = function()
  for _, name in ipairs({ "BAMBOO_API_KEY", "STARTLUX_API_KEY" }) do
    local value = vim.env[name]
    if type(value) == "string" and trim(value) ~= "" then return trim(value) end
  end

  local configured = opt("api_key")
  if type(configured) == "string" and trim(configured) ~= "" then return trim(configured) end

  local path = opt("key_file")
  if type(path) == "string" and path ~= "" then
    path = fn.expand(path)
    if fn.filereadable(path) == 1 then
      local handle = io.open(path, "r")
      if handle then
        local text = trim(handle:read("*a") or "")
        handle:close()
        if text ~= "" then return text end
      end
    end
  end

  return nil
end

-- ---------------------------------------------------------------------------
-- window -> chunks
-- ---------------------------------------------------------------------------

---Blank-line separated blocks in `[first, last]`: every block is one chunk, i.e.
---one paragraph's Chinese line(s) followed by its English line(s).
---@param first integer
---@param last integer
---@return { start: integer, stop: integer, lines: string[] }[]
H.blocks = function(first, last)
  local blocks, current = {}, nil
  for lnum = first, last do
    local text = fn.getline(lnum)
    if trim(text) == "" then
      current = nil
    else
      if not current then
        current = { start = lnum, stop = lnum, lines = {} }
        blocks[#blocks + 1] = current
      end
      current.stop = lnum
      current.lines[#current.lines + 1] = text
    end
  end
  return blocks
end

---One line per chunk, showing the head of every line in it.
---@param block { start: integer, stop: integer, lines: string[] }
---@return string
H.describe = function(block)
  local parts = {}
  for _, text in ipairs(block.lines) do
    parts[#parts + 1] = clip(trim(text), 40)
  end
  return ("行%d: %s"):format(block.start, table.concat(parts, " / "))
end

---@param block { start: integer, stop: integer }
---@param first integer
---@param last integer
---@return boolean
H.is_truncated = function(block, first, last)
  local last_line = api.nvim_buf_line_count(0)
  if block.start == first and first > 1 and trim(fn.getline(first - 1)) ~= "" then
    return true
  end
  if block.stop == last and last < last_line and trim(fn.getline(last + 1)) ~= "" then
    return true
  end
  return false
end

---Blocks that lie completely inside `[first, last]`. A chunk cut by the edge
---of the window is not offered as a choice: the missing lines would make an
---otherwise aligned chunk look unpaired.
---@param first integer
---@param last integer
---@return { start: integer, stop: integer, lines: string[] }[]
H.complete_blocks = function(first, last)
  local blocks = H.blocks(first, last)
  local complete = {}
  for _, block in ipairs(blocks) do
    if not H.is_truncated(block, first, last) then complete[#complete + 1] = block end
  end
  return complete
end

---@param first integer
---@param last integer
---@return string
H.build_state = function(first, last)
  local lines = {
    "你是双语行对齐检查器。下面是编辑器当前窗口的内容，每行以「行号|」开头。",
    "空行分隔 chunk；每个 chunk 是同一段文字的中文行（上面，译文）与英文行（下面，原文）。",
    "同一个 chunk 内的中文与英文应当是同一段内容的译文与原文。",
    "",
    "窗口内容：",
  }
  for lnum = first, last do
    lines[#lines + 1] = ("%d|%s"):format(lnum, fn.getline(lnum))
  end
  lines[#lines + 1] = ""
  if #H.complete_blocks(first, last) < #H.blocks(first, last) then
    lines[#lines + 1] = "注意：窗口首/尾有不完整的 chunk，它们不参与选择；只判断完整显示在窗口内的 chunk。"
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = "任务：从上往下找第一个未对齐的 chunk —— 该 chunk 的中文开头与英文开头不是同一句话的对应内容。"
  lines[#lines + 1] = "只看每对的开头（前几个词）即可，不必通读整行；一处错位会传播到下面所有 chunk，所以只需要第一个。"
  return table.concat(lines, "\n")
end

---@param blocks { start: integer, stop: integer, lines: string[] }[]
---@return table
H.build_questions = function(blocks)
  local criteria = {}
  local limit = math.max(1, tonumber(opt("max_options")) or #blocks)
  for index, block in ipairs(blocks) do
    if index > limit then break end
    criteria[tostring(block.start)] = H.describe(block)
  end
  criteria["none"] = "窗口内所有 chunk 都已对齐"
  return {
    first_unpair = {
      type = "choice",
      instructions = "哪一个 chunk 是第一个未对齐的？选择该 chunk 第一行的行号。",
      criteria = criteria,
    },
  }
end

-- ---------------------------------------------------------------------------
-- operation decision (second request)
-- ---------------------------------------------------------------------------

---@return integer
H.lang_num = function()
  local ok, config = pcall(require, "interlaced.config")
  if not ok or type(config) ~= "table" then return 2 end
  return math.max(1, tonumber(config.lang_num) or 2)
end

---1-based language position in a chunk, or nil for the blank separator.
---@param lnum integer
---@return integer|nil
H.line_role = function(lnum)
  local role = lnum % (H.lang_num() + 1)
  if role == 0 then return nil end
  return role
end

---@param lnum integer
---@return string
H.line_tag = function(lnum)
  local role = H.line_role(lnum)
  if role == nil then return "空行" end
  if H.lang_num() == 2 then
    return role == 1 and "中文" or "英文"
  end
  return ("L%d"):format(role)
end

---The block that contains `lnum`, read from the buffer rather than the window.
---@param lnum integer
---@return { start: integer, stop: integer, lines: string[] }|nil
H.block_around = function(lnum)
  local last = api.nvim_buf_line_count(0)
  if lnum < 1 or lnum > last or trim(fn.getline(lnum)) == "" then return nil end
  local start, stop = lnum, lnum
  while start > 1 and trim(fn.getline(start - 1)) ~= "" do start = start - 1 end
  while stop < last and trim(fn.getline(stop + 1)) ~= "" do stop = stop + 1 end
  return { start = start, stop = stop, lines = fn.getline(start, stop) }
end

---@param block { start: integer, stop: integer }
---@return { start: integer, stop: integer, lines: string[] }|nil
H.block_before = function(block)
  local lnum = block.start - 1
  while lnum >= 1 and trim(fn.getline(lnum)) == "" do lnum = lnum - 1 end
  if lnum < 1 then return nil end
  return H.block_around(lnum)
end

---@param block { start: integer, stop: integer }
---@return { start: integer, stop: integer, lines: string[] }|nil
H.block_after = function(block)
  local last = api.nvim_buf_line_count(0)
  local lnum = block.stop + 1
  while lnum <= last and trim(fn.getline(lnum)) == "" do lnum = lnum + 1 end
  if lnum > last then return nil end
  return H.block_around(lnum)
end

---@param block { start: integer, stop: integer }
---@return integer|nil
H.last_language_line = function(block)
  for lnum = block.stop, block.start, -1 do
    if H.line_role(lnum) ~= nil then return lnum end
  end
  return nil
end

---@param lnum integer
---@param where string
---@return string
local function line_ref(lnum, where)
  return ("行%d（%s，%s）「%s」"):format(
    lnum, H.line_tag(lnum), where, clip(trim(fn.getline(lnum)), 28))
end

---@param text string
---@param width integer
---@return string
local function clip_tail(text, width)
  if fn.strchars(text) <= width then return text end
  return "…" .. fn.strcharpart(text, fn.strchars(text) - width, width)
end

local SENTENCE_PUNCT = {
  ["."] = true, ["!"] = true, ["?"] = true, [";"] = true,
  ["。"] = true, ["！"] = true, ["？"] = true, ["；"] = true,
}
local CLAUSE_PUNCT = {
  [","] = true, [":"] = true, ["、"] = true, ["，"] = true, ["："] = true,
  ["—"] = true, ["…"] = true,
}
local CLOSERS = {
  ["”"] = true, ["’"] = true, ["」"] = true, ["』"] = true, ["）"] = true,
  [")"] = true, ["]"] = true, ["】"] = true, ["》"] = true, ["〉"] = true,
}
local CONJUNCTIONS = {
  "但是", "可是", "然而", "不过", "因为", "所以", "因此", "于是", "然后",
  "接着", "同时", "如果", "虽然", "尽管", "当", "最后", "首先", "其次",
  "此外", "以及", "或者", "而", "但", "却",
}

---Split one UTF-8 line into characters and their 1-based byte positions.
---@param line string
---@return string[] chars
---@return integer[] cols `cols[i]` is the byte column of char `i`; the last item is `#line + 1`
H.char_cols = function(line)
  local chars = fn.split(line, "\\zs")
  local cols = {}
  local byte = 1
  for i, ch in ipairs(chars) do
    cols[i] = byte
    byte = byte + #ch
  end
  cols[#chars + 1] = byte
  return chars, cols
end

---Possible split points for an inline operation. `col` is a 1-based byte
---column; the left part ends at `col - 1` and the right part starts at `col`.
---@param lnum integer
---@return { col: integer, left: string, right: string }[]
H.split_candidates = function(lnum)
  local line = fn.getline(lnum)
  local chars, cols = H.char_cols(line)
  local count = #chars
  if count < 2 then return {} end

  local candidates, seen = {}, {}
  local function add(index, priority)
    if index < 2 or index > count then return end
    local col = cols[index]
    if seen[col] then return end
    local left, right = trim(line:sub(1, col - 1)), trim(line:sub(col))
    if left == "" or right == "" then return end
    seen[col] = true
    candidates[#candidates + 1] = {
      col = col,
      left = left,
      right = right,
      priority = priority or 2,
    }
  end

  -- After punctuation/closing quotes, before the next word or sentence. On
  -- English lines a punctuation mark only counts when it is followed by
  -- whitespace, a closing quote, or the end of the line, so "3.14" and
  -- "e.g." do not become split points.
  local english = H.line_role(lnum) ~= 1
  for i, ch in ipairs(chars) do
    if SENTENCE_PUNCT[ch] or CLAUSE_PUNCT[ch] then
      local next_is_boundary = i == count
        or CLOSERS[chars[i + 1]] ~= nil
        or chars[i + 1]:match("^%s$") ~= nil
      if not english or next_is_boundary then
        local j = i + 1
        while j <= count and (CLOSERS[chars[j]] or chars[j]:match("^%s$")) do j = j + 1 end
        add(j, 1)
      end
    end
  end

  if H.line_role(lnum) == 1 then
    -- Chinese: split before common discourse markers, and allow any character
    -- boundary when a line has no punctuation at all.
    for _, token in ipairs(CONJUNCTIONS) do
      local token_chars = fn.split(token, "\\zs")
      for i = 2, count - #token_chars + 1 do
        local matched = true
        for k = 1, #token_chars do
          if chars[i + k - 1] ~= token_chars[k] then
            matched = false
            break
          end
        end
        if matched then add(i, 1) end
      end
    end
    for i = 2, count do add(i, 2) end
  else
    -- English: every word start after a space, so a word is never cut in half.
    for i = 2, count do
      if chars[i]:match("^[%w]$") and chars[i - 1]:match("^%s$") then add(i, 2) end
    end
  end

  local max = math.max(1, tonumber(opt("split_max_options")) or 60)
  if #candidates > max then
    -- Keep punctuation/conjunction candidates, then sample the rest evenly so a
    -- long line still offers split points across its whole width.
    local important, rest = {}, {}
    for _, candidate in ipairs(candidates) do
      if candidate.priority == 1 then
        important[#important + 1] = candidate
      else
        rest[#rest + 1] = candidate
      end
    end
    table.sort(important, function(a, b) return a.col < b.col end)
    table.sort(rest, function(a, b) return a.col < b.col end)

    local kept = important
    local slots = max - #kept
    if slots > 0 and #rest > 0 then
      if slots >= #rest then
        vim.list_extend(kept, rest)
      else
        for i = 1, slots do
          kept[#kept + 1] = rest[math.floor((i - 1) * #rest / slots) + 1]
        end
      end
    end
    if #kept > max then
      table.sort(kept, function(a, b) return a.col < b.col end)
      local sliced = {}
      for i = 1, max do sliced[i] = kept[i] end
      kept = sliced
    end
    candidates = kept
  end

  table.sort(candidates, function(a, b) return a.col < b.col end)
  return candidates
end

---Choice criteria for an inline split, keyed by `col:<byte>`.
---@param candidates { col: integer, left: string, right: string }[]
---@return table<string, string>
H.split_options = function(candidates)
  local options = {}
  for _, candidate in ipairs(candidates) do
    options["col:" .. candidate.col] = ("在「%s」与「%s」之间切分（第%d字节）。"):format(
      clip_tail(candidate.left, 24), clip(candidate.right, 40), candidate.col)
  end
  options["none"] = "没有安全的分界点：这一行不能可靠地拆开，保留整行。"
  return options
end

---Choice criteria for the second request. Every key is `operation:line`.
---@param cur { start: integer, stop: integer, lines: string[] }
---@param prev { start: integer, stop: integer, lines: string[] }|nil
---@param nxt { start: integer, stop: integer, lines: string[] }|nil
---@return table<string, string>
H.operation_options = function(cur, prev, nxt)
  local criteria = {}
  local function add(key, description) criteria[key] = description end

  local cur_lines = {}
  for lnum = cur.start, cur.stop do
    if H.line_role(lnum) ~= nil then cur_lines[#cur_lines + 1] = lnum end
  end

  local next_lines = {}
  if nxt then
    for lnum = nxt.start, nxt.stop do
      if H.line_role(lnum) ~= nil then next_lines[#next_lines + 1] = lnum end
    end
  end

  ---@param lnum integer
  ---@return boolean
  local function can_split(lnum) return #H.split_candidates(lnum) > 0 end

  if prev then
    for _, lnum in ipairs(cur_lines) do
      add("push_up:" .. lnum, ("把%s整行上并到上一块同一语言行的末尾；行%d 留空，下面整体上移。"):format(
        line_ref(lnum, "当前块"), lnum))
      if can_split(lnum) then
        add("push_up_left_part:" .. lnum, ("把%s分界点左侧的文本上并到上一块同一语言行的末尾，行%d 保留右侧；分界点在下一步选择。"):format(
          line_ref(lnum, "当前块"), lnum))
      end
    end
    add("push_up_pair:" .. cur.start, ("把当前块（行%d-行%d）的每一行上并到上一块对应行的末尾；整块上移。"):format(
      cur.start, cur.stop))
  end

  if nxt then
    for _, lnum in ipairs(cur_lines) do
      add("pull_below:" .. lnum, ("把下一块同一语言行整行拉到%s的末尾；下一块该行留空，下面整体上移。"):format(
        line_ref(lnum, "当前块")))
      add("push_down:" .. lnum, ("把%s整行下推到下一块同一语言行的开头；行%d 留空，下面整体下移。"):format(
        line_ref(lnum, "当前块"), lnum))
      if can_split(lnum) then
        add("push_down_right_part:" .. lnum, ("把%s分界点右侧的文本下推到下一块同一语言行的开头，行%d 保留左侧；分界点在下一步选择。"):format(
          line_ref(lnum, "当前块"), lnum))
      end
    end
    add("pull_below_pair:" .. cur.start, ("把下一块每一行整行拉到当前块（行%d-行%d）对应行的末尾；下一块上移。"):format(
      cur.start, cur.stop))

    for _, lnum in ipairs(next_lines) do
      if can_split(lnum) then
        add("push_up_left_part:" .. lnum, ("把%s分界点左侧的文本上并到当前块同一语言行的末尾，行%d 保留右侧；分界点在下一步选择。"):format(
          line_ref(lnum, "下一块"), lnum))
      end
    end

    if prev then
      local tail = H.last_language_line(prev)
      if tail then
        add("push_down:" .. tail, ("把上一块最后一行%s整行下推到下一块同一语言行的开头；这通常是上一对尾部多出的内容。"):format(
          line_ref(tail, "上一块末行")))
        if can_split(tail) then
          add("push_down_right_part:" .. tail, ("把%s分界点右侧的文本下推到当前块同一语言行的开头，行%d 保留左侧；这通常是上一对尾部多出的内容。"):format(
            line_ref(tail, "上一块末行"), tail))
        end
      end
    end
  end

  for _, lnum in ipairs(cur_lines) do
    add("leave_alone:" .. lnum, ("保留%s，把当前块另一语言行下推并放 '-' 占位，光标进入下一块。"):format(
      line_ref(lnum, "当前块")))
  end

  add("none", "不要移动任何行：当前整行/pair/行内操作都不能安全修复这个边界。")
  return criteria
end

---Append one chunk to a request state, with absolute line numbers.
---@param lines string[]
---@param title string
---@param block { start: integer, stop: integer }|nil
local function append_block(lines, title, block)
  if not block then return end
  lines[#lines + 1] = title
  for lnum = block.start, block.stop do
    lines[#lines + 1] = ("%d|%s|%s"):format(lnum, H.line_tag(lnum), fn.getline(lnum))
  end
  lines[#lines + 1] = ""
end

---@param cur { start: integer, stop: integer, lines: string[] }
---@param prev { start: integer, stop: integer, lines: string[] }|nil
---@param nxt { start: integer, stop: integer, lines: string[] }|nil
---@return string
H.build_operation_state = function(cur, prev, nxt)
  local lines = {
    "你是双语行对齐检查器。下面是第一个未对齐位置及其上下文，每行以「行号|语言|内容」开头。",
    "空行分隔 chunk；每个 chunk 是中文行（上，译文）与英文行（下，原文）。",
    "对齐的本质是分段边界一一对应：一个 pair 对齐 ⟺ 上一 pair 结束时中英文停在对应位置，且本 pair 的中文头对应英文头。",
    "只看每个 pair 的开头（前几个词），不必通读整行。",
    "判责优先：若当前块的中文头对应上一块英文行的结尾，病灶在上一块尾部，而不是当前块。",
    "已确认当前块是第一个未对齐的 chunk。",
    "",
  }

  append_block(lines, "上一块：", prev)
  append_block(lines, "当前块（第一个未对齐）：", cur)
  append_block(lines, "下一块：", nxt)

  lines[#lines + 1] = "操作说明："
  lines[#lines + 1] = "- push_up：目标行整行上并到上一块同一语言行的末尾，目标行留空，下面整体上移。"
  lines[#lines + 1] = "- pull_below：下一块同一语言行整行拉到目标行末尾，下一块该行留空，下面整体上移。"
  lines[#lines + 1] = "- push_down：目标行整行下推到下一块同一语言行的开头，目标行留空，下面整体下移。"
  lines[#lines + 1] = "- push_up_pair / pull_below_pair：整块每一行对应地上并 / 下拉。"
  lines[#lines + 1] = "- push_up_left_part：目标行分界点左侧的文本上并到上一块同一语言行的末尾，右侧保留在目标行。"
  lines[#lines + 1] = "- push_down_right_part：目标行分界点右侧的文本下推到下一块同一语言行的开头，左侧保留在目标行。"
  lines[#lines + 1] = "- 行内操作的分界点会在下一步单独选择；目标行也可以是上一块末行或下一块的行。"
  lines[#lines + 1] = "- leave_alone：保留目标行，当前块另一语言行下推并放 '-' 占位。"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "判断规则："
  lines[#lines + 1] = "1. 若当前块中文头对应英文下一行开头，中文开头多出内容：优先 push_down 或 push_down_right_part 当前块中文行。"
  lines[#lines + 1] = "2. 若当前块中文头对应英文上一行结尾，上一块英文尾部多出内容：优先 push_down 或 push_down_right_part 上一块英文末行。"
  lines[#lines + 1] = "3. 若整行/整块需要移动，选 push_up、push_down 或对应的 pair 操作。"
  lines[#lines + 1] = "4. 只有行首或行尾的一部分需要移动时，选 push_up_left_part 或 push_down_right_part；不要为了行内切分而整行移动。"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "任务：选择一个原子操作，使当前块的中英文边界恢复对应；不要移动已对齐的上方内容。"
  return table.concat(lines, "\n")
end

---@param cur { start: integer, stop: integer, lines: string[] }
---@param prev { start: integer, stop: integer, lines: string[] }|nil
---@param nxt { start: integer, stop: integer, lines: string[] }|nil
---@return string body
---@return table<string, string> options
H.build_operation_payload = function(cur, prev, nxt)
  local options = H.operation_options(cur, prev, nxt)
  local body = vim.json.encode({
    model = opt("model"),
    state = H.build_operation_state(cur, prev, nxt),
    questions = {
      operation = {
        type = "choice",
        instructions = "哪一个整行/pair/行内操作最可能一步修复这个边界？只选一个；若病灶在上一对尾部，选对上一块末行的操作。",
        criteria = options,
      },
    },
    think_mode = opt("think_mode"),
    allow_none = false,
  })
  return body, options
end

---@param cur { start: integer, stop: integer, lines: string[] }
---@param prev { start: integer, stop: integer, lines: string[] }|nil
---@param nxt { start: integer, stop: integer, lines: string[] }|nil
---@param answer { op: string, lnum: integer }
---@return string
H.build_split_state = function(cur, prev, nxt, answer)
  local side = answer.op == "push_up_left_part"
    and "左侧文本上并到上一块同一语言行的末尾，右侧保留在目标行。"
    or "右侧文本下推到下一块同一语言行的开头，左侧保留在目标行。"
  local lines = {
    "你是双语行对齐检查器。已经选定一个行内操作，请为它选择分界点。",
    "分界点把目标行切成左右两段，两段都必须非空，并尽量落在完整的词/句边界。",
    ("操作：%s —— %s"):format(answer.op, side),
    ("目标行：%d|%s|%s"):format(answer.lnum, H.line_tag(answer.lnum), fn.getline(answer.lnum)),
    "",
  }

  append_block(lines, "上一块：", prev)
  append_block(lines, "当前块（第一个未对齐）：", cur)
  append_block(lines, "下一块：", nxt)

  lines[#lines + 1] = "任务：从候选中选出最符合语义的分界点；若没有安全的位置，选 none。"
  return table.concat(lines, "\n")
end

---@param cur { start: integer, stop: integer, lines: string[] }
---@param prev { start: integer, stop: integer, lines: string[] }|nil
---@param nxt { start: integer, stop: integer, lines: string[] }|nil
---@param answer { op: string, lnum: integer }
---@return string|nil body
---@return table<string, string>|nil options
H.build_split_payload = function(cur, prev, nxt, answer)
  local candidates = H.split_candidates(answer.lnum)
  if #candidates == 0 then return nil end

  local options = H.split_options(candidates)
  local body = vim.json.encode({
    model = opt("model"),
    state = H.build_split_state(cur, prev, nxt, answer),
    questions = {
      split = {
        type = "choice",
        instructions = "分界点应该落在哪两个词/句之间？只选一个；没有安全分界点时选 none。",
        criteria = options,
      },
    },
    think_mode = opt("think_mode"),
    allow_none = false,
  })
  return body, options
end

---@param text string
---@param options table<string, string>
---@return table|nil answer `{ key, col, confidence }`, or `{ key = "none" }`
---@return string|nil error
---@return table|nil raw
H.parse_split = function(text, options)
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return nil, "StartLux did not answer with JSON: " .. clip(trim(text), 120)
  end
  if data.error then
    local message = type(data.error) == "table" and (data.error.message or data.error.code) or data.error
    return nil, tostring(message)
  end

  local answer = type(data.answers) == "table" and data.answers.split or nil
  if type(answer) ~= "table" then
    return nil, "StartLux returned no answers.split"
  end

  local choice = answer.choice
  if choice == nil or choice == vim.NIL then
    return nil, "StartLux returned no split choice"
  end
  if choice == "none" then
    return { key = "none", confidence = tonumber(answer.confidence) }, nil, data
  end
  if not options[choice] then
    return nil, "unreadable split: " .. tostring(choice)
  end

  local col = tostring(choice):match("^col:(%d+)$")
  if not col then
    return nil, "unreadable split: " .. tostring(choice)
  end
  return {
    key = choice,
    col = tonumber(col),
    confidence = tonumber(answer.confidence),
  }, nil, data
end

---@param text string
---@param options table<string, string>
---@return table|nil answer `{ key, op, lnum, confidence }`, or `{ op = "none" }`
---@return string|nil error
---@return table|nil raw
H.parse_operation = function(text, options)
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return nil, "StartLux did not answer with JSON: " .. clip(trim(text), 120)
  end
  if data.error then
    local message = type(data.error) == "table" and (data.error.message or data.error.code) or data.error
    return nil, tostring(message)
  end

  local answer = type(data.answers) == "table" and data.answers.operation or nil
  if type(answer) ~= "table" then
    return nil, "StartLux returned no answers.operation"
  end

  local choice = answer.choice
  if choice == nil or choice == vim.NIL then
    return nil, "StartLux returned no operation choice"
  end
  if choice == "none" then
    return { key = "none", op = "none", confidence = tonumber(answer.confidence) }, nil, data
  end
  if not options[choice] then
    return nil, "unreadable operation: " .. tostring(choice)
  end

  local op, lnum = tostring(choice):match("^([%a_]+):(%d+)$")
  if not op or not lnum then
    return nil, "unreadable operation: " .. tostring(choice)
  end
  return {
    key = choice,
    op = op,
    lnum = tonumber(lnum),
    confidence = tonumber(answer.confidence),
  }, nil, data
end

---The JSON body sent to POST `/v1/decisions`.
---@param first integer
---@param last integer
---@return string
H.build_payload = function(first, last)
  local blocks = H.complete_blocks(first, last)
  return vim.json.encode({
    model = opt("model"),
    state = H.build_state(first, last),
    questions = H.build_questions(blocks),
    think_mode = opt("think_mode"),
    allow_none = false,
  })
end

-- ---------------------------------------------------------------------------
-- POST /decisions via curl
-- ---------------------------------------------------------------------------

---@param err string|nil
---@param text string|nil
---@param cb fun(err: string|nil, text: string|nil)
---@return fun() cancel
H.post = function(body, cb)
  local key = H.api_key()
  if not key then
    cb("no API key: set $BAMBOO_API_KEY or write it to " .. fn.expand(tostring(opt("key_file") or "")))
    return function() end
  end

  local curl = tostring(opt("curl") or "curl")
  if fn.executable(curl) == 0 then
    cb(("`%s` is not executable; set vim.g.interlaced.startlux.curl"):format(curl))
    return function() end
  end

  local url = tostring(opt("base_url")):gsub("/+$", "") .. "/decisions"
  local cmd = {
    curl,
    "-sS",
    "--max-time",
    tostring(tonumber(opt("timeout_s")) or 20),
    "-X",
    "POST",
    url,
    "-H",
    "Authorization: Bearer " .. key,
    "-H",
    "Content-Type: application/json",
    "--data-binary",
    "@-",
  }

  local finished = false
  local handle = vim.system(cmd, { stdin = body, text = true }, function(result)
    if finished then return end
    finished = true
    vim.schedule(function()
      if result.code ~= 0 then
        local stderr = trim(result.stderr or "")
        return cb(stderr ~= "" and stderr or ("curl exited with %d"):format(result.code))
      end
      cb(nil, result.stdout or "")
    end)
  end)

  return function()
    if finished then return end
    finished = true
    pcall(handle.kill, handle, "sigterm")
  end
end

-- ---------------------------------------------------------------------------
-- response
-- ---------------------------------------------------------------------------

---@param text string
---@return integer|string|nil answer a buffer line number, `"none"`, or nil on error
---@return string|nil error
---@return table|nil raw
H.parse_answer = function(text)
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return nil, "StartLux did not answer with JSON: " .. clip(trim(text), 120)
  end
  if data.error then
    local message = type(data.error) == "table" and (data.error.message or data.error.code) or data.error
    return nil, tostring(message)
  end

  local answer = type(data.answers) == "table" and data.answers.first_unpair or nil
  if type(answer) ~= "table" then
    return nil, "StartLux returned no answers.first_unpair"
  end

  local choice = answer.choice
  if choice == nil or choice == vim.NIL or choice == "none" then
    return "none", nil, data
  end
  local lnum = tonumber(choice)
  if not lnum then
    return nil, "unreadable first_unpair: " .. tostring(choice), data
  end
  return math.floor(lnum), nil, data
end

-- ---------------------------------------------------------------------------
-- jump + flash
-- ---------------------------------------------------------------------------

api.nvim_set_hl(0, "InterlacedUnpairFlash", { default = true, link = "IncSearch" })

---@param lnum integer
---@param blocks { start: integer, stop: integer }[]
---@param first integer
---@param last integer
---@return { start: integer, stop: integer }
H.block_at = function(lnum, blocks, first, last)
  if lnum < first or lnum > last then
    -- the model may have counted window-relative lines instead
    local relative = first + lnum - 1
    if relative >= first and relative <= last then lnum = relative end
  end
  for _, block in ipairs(blocks) do
    if lnum >= block.start and lnum <= block.stop then return block end
  end
  if lnum < first then return blocks[1] end
  if lnum > last then return blocks[#blocks] end
  for _, block in ipairs(blocks) do
    if lnum <= block.start then return block end
  end
  return blocks[#blocks]
end

---@param block { start: integer, stop: integer }
---@param cursor_lnum integer|nil line to put the cursor on; defaults to the block start
---@param cursor_col integer|nil 1-based byte column, e.g. the split point of an inline operation
H.reveal = function(block, cursor_lnum, cursor_col)
  local win = api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  local ns = api.nvim_create_namespace("interlaced.startlux")
  local last = api.nvim_buf_line_count(buf)
  local start = math.min(math.max(block.start, 1), last)
  local stop = math.min(math.max(block.stop, start), last)
  local target = math.min(math.max(cursor_lnum or start, start), stop)
  local col = 0
  if cursor_col then
    local max_col = math.max(0, #fn.getline(target) - 1)
    col = math.min(math.max(cursor_col - 1, 0), max_col)
  end

  pcall(api.nvim_win_set_cursor, win, { target, col })
  pcall(vim.cmd, "normal! zz")

  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local group = tostring(opt("highlight_group") or "InterlacedUnpairFlash")
  for lnum = start, stop do
    pcall(api.nvim_buf_set_extmark, buf, ns, lnum - 1, 0, { line_hl_group = group })
  end

  if M.flash_timer and not M.flash_timer:is_closing() then
    M.flash_timer:stop()
    M.flash_timer:close()
  end
  M.flash_timer = uv.new_timer()
  M.flash_timer:start(math.max(1, tonumber(opt("highlight_ms")) or 1200), 0, function()
    vim.schedule(function()
      if M.flash_timer and not M.flash_timer:is_closing() then
        M.flash_timer:stop()
        M.flash_timer:close()
      end
      if api.nvim_buf_is_valid(buf) then
        api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      end
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- actions
-- ---------------------------------------------------------------------------

---Operations that `startlux_apply` may execute. They are exactly the whole-line
---and pair choices `startlux_op` offers.
H.OPERATIONS = {
  push_up = true,
  pull_below = true,
  push_down = true,
  push_up_pair = true,
  pull_below_pair = true,
  push_up_left_part = true,
  push_down_right_part = true,
  leave_alone = true,
}

H.PARTIAL_OPERATIONS = {
  push_up_left_part = true,
  push_down_right_part = true,
}

---@param op string
---@return boolean
H.is_partial = function(op) return H.PARTIAL_OPERATIONS[op] == true end

---Execute one operation chosen by the model. The cursor is moved with
---`nvim_win_set_cursor` rather than `k`/`j`, so user mappings cannot interfere.
---@param answer { op: string, lnum: integer }
---@return boolean ok
---@return string|nil error
H.apply_operation = function(answer)
  local name = answer and answer.op
  if not H.OPERATIONS[name] then
    return false, "unknown operation: " .. tostring(name)
  end
  if H.is_partial(name) and not answer.cnum then
    return false, "missing split column for " .. tostring(name)
  end

  local ok, reposition = pcall(require, "interlaced.reposition")
  if not ok or type(reposition.action) ~= "table" then
    return false, "interlaced.reposition is not available"
  end
  local action = reposition.action[name]
  if type(action) ~= "function" then
    return false, "operation is not available: " .. tostring(name)
  end

  local col = H.is_partial(name) and answer.cnum - 1 or 0
  pcall(api.nvim_win_set_cursor, 0, { answer.lnum, math.max(0, col) })
  local before = api.nvim_buf_get_changedtick(0)
  local args = { tostring(answer.lnum) }
  if H.is_partial(name) then args[2] = tostring(answer.cnum) end
  local applied, err = pcall(action, { fargs = args })
  if not applied then return false, tostring(err) end
  if api.nvim_buf_get_changedtick(0) == before then
    return false, ("%s made no change at line %d"):format(name, answer.lnum)
  end
  return true
end

---Scroll the current window one page forward, without using user mappings.
---@return boolean moved
H.page_down = function()
  local before = fn.winsaveview().topline
  vim.cmd("normal! \6") -- <C-F>
  return fn.winsaveview().topline ~= before
end

---Locate the first unaligned chunk, then ask for one whole-line/pair operation.
---@param apply boolean execute the suggestion instead of only revealing it
H.run_operation = function(apply)
  if M.pending then
    vim.notify("interlaced.startlux: the previous request is still running", vim.log.levels.WARN)
    return
  end

  local buf = api.nvim_get_current_buf()
  local tick = api.nvim_buf_get_changedtick(buf)
  local first = math.max(1, fn.line("w0"))
  local last = math.max(1, fn.line("w$"))
  local all_blocks = H.blocks(first, last)
  local blocks = H.complete_blocks(first, last)
  if #blocks < 2 then
    if apply then
      local moved = H.page_down()
      vim.notify(moved
        and "interlaced.startlux: no unpair in this window; moved one page down"
        or "interlaced.startlux: no unpair in this window and no next page",
        vim.log.levels.INFO)
    else
      vim.notify("interlaced.startlux: the window has nothing to compare", vim.log.levels.WARN)
    end
    return
  end

  local body = H.build_payload(first, last)
  local started = uv.hrtime()
  local function elapsed_ms() return (uv.hrtime() - started) / 1e6 end
  local entry = { cancel = function() end }
  M.pending = entry
  M.last_op = nil

  local function fail(message)
    if M.pending == entry then M.pending = nil end
    vim.notify("interlaced.startlux: " .. tostring(message), vim.log.levels.ERROR)
  end

  ---Abort if the user switched buffers or edited while the request was in flight.
  local function stale()
    return not api.nvim_buf_is_valid(buf)
      or api.nvim_get_current_buf() ~= buf
      or api.nvim_buf_get_changedtick(buf) ~= tick
  end

  entry.cancel = H.post(body, function(err, text)
    if M.pending ~= entry then return end
    if err then return fail(err) end
    if stale() then return fail("buffer changed during the request; discarded") end

    local lnum, message = H.parse_answer(text or "")
    if not lnum then return fail(message) end
    if lnum == "none" then
      M.pending = nil
      local elapsed = elapsed_ms()
      if apply then
        local moved = H.page_down()
        vim.notify(moved
          and ("interlaced.startlux: no unpair in this window; moved one page down (%.0f ms)"):format(elapsed)
          or ("interlaced.startlux: no unpair in this window and no next page (%.0f ms)"):format(elapsed),
          vim.log.levels.INFO)
      else
        vim.notify(("interlaced.startlux: no unaligned chunk in this window (%.0f ms)"):format(elapsed), vim.log.levels.INFO)
      end
      return
    end

    local block = H.block_at(lnum, all_blocks, first, last)
    local complete = false
    for _, candidate in ipairs(blocks) do
      if candidate.start == block.start then
        complete = true
        break
      end
    end
    if not complete then
      M.pending = nil
      local elapsed = elapsed_ms()
      if apply then
        local moved = H.page_down()
        vim.notify(moved
          and ("interlaced.startlux: no complete unpair in this window; moved one page down (%.0f ms)"):format(elapsed)
          or ("interlaced.startlux: no complete unpair in this window and no next page (%.0f ms)"):format(elapsed),
          vim.log.levels.INFO)
      else
        vim.notify(("interlaced.startlux: no complete unaligned chunk in this window (%.0f ms)"):format(elapsed), vim.log.levels.INFO)
      end
      return
    end

    local prev = H.block_before(block)
    local nxt = H.block_after(block)
    local op_body, options = H.build_operation_payload(block, prev, nxt)
    M.last_op = { body = op_body, options = options, block = block, first = first, last = last }

    entry.cancel = H.post(op_body, function(op_err, op_text)
      if M.pending ~= entry then return end

      if op_err then
        M.pending = nil
        vim.notify("interlaced.startlux: " .. op_err, vim.log.levels.ERROR)
        return
      end
      if stale() then
        M.pending = nil
        vim.notify("interlaced.startlux: buffer changed during the request; discarded", vim.log.levels.ERROR)
        return
      end

      local answer, op_message = H.parse_operation(op_text or "", options)
      if not answer then
        M.pending = nil
        vim.notify("interlaced.startlux: " .. tostring(op_message), vim.log.levels.ERROR)
        return
      end

      if answer.op == "none" then
        M.pending = nil
        H.reveal(block)
        vim.notify(("interlaced.startlux: no safe operation suggested (%.0f ms)"):format(elapsed_ms()), vim.log.levels.INFO)
        return
      end

      local target_block = H.block_around(answer.lnum) or block

      ---@param final table
      ---@param split table|nil
      local function finish(final, split)
        M.pending = nil
        M.last_op.answer = final
        local col = split and split.col or nil
        local where = col and (" col %d"):format(col) or ""
        local elapsed = elapsed_ms()

        if apply then
          local applied, apply_err = H.apply_operation(final)
          if not applied then
            H.reveal(target_block, final.lnum, col)
            vim.notify(("interlaced.startlux: cannot apply %s: %s"):format(final.op, tostring(apply_err)),
              vim.log.levels.ERROR)
            return
          end
          vim.notify(("interlaced.startlux: first unpair line %d; applied %s at line %d%s (%s, confidence %.2f, %.0f ms); :Interlaced undo to revert"):format(
            block.start, final.op, final.lnum, where, H.line_tag(final.lnum), final.confidence or 0, elapsed),
            vim.log.levels.INFO)
          return
        end

        H.reveal(target_block, final.lnum, col)
        vim.notify(("interlaced.startlux: first unpair line %d; suggest %s at line %d%s (%s, confidence %.2f, %.0f ms)"):format(
          block.start, final.op, final.lnum, where, H.line_tag(final.lnum), final.confidence or 0, elapsed),
          vim.log.levels.INFO)
      end

      if not H.is_partial(answer.op) then
        finish(answer)
        return
      end

      local split_body, split_options = H.build_split_payload(block, prev, nxt, answer)
      if not split_body then
        M.pending = nil
        H.reveal(target_block, answer.lnum)
        vim.notify(("interlaced.startlux: no safe split point for %s at line %d (%s)"):format(
          answer.op, answer.lnum, H.line_tag(answer.lnum)), vim.log.levels.WARN)
        return
      end
      M.last_op.split_body = split_body
      M.last_op.split_options = split_options

      entry.cancel = H.post(split_body, function(split_err, split_text)
        if M.pending ~= entry then return end
        if split_err then
          M.pending = nil
          vim.notify("interlaced.startlux: " .. split_err, vim.log.levels.ERROR)
          return
        end
        if stale() then
          M.pending = nil
          vim.notify("interlaced.startlux: buffer changed during the request; discarded", vim.log.levels.ERROR)
          return
        end

        local split, split_message = H.parse_split(split_text or "", split_options)
        if not split then
          M.pending = nil
          vim.notify("interlaced.startlux: " .. tostring(split_message), vim.log.levels.ERROR)
          return
        end
        if split.key == "none" then
          M.pending = nil
          H.reveal(target_block, answer.lnum)
          vim.notify(("interlaced.startlux: no safe split point for %s at line %d (%.0f ms)"):format(
            answer.op, answer.lnum, elapsed_ms()), vim.log.levels.INFO)
          return
        end

        M.last_op.split = split
        answer.cnum = split.col
        finish(answer, split)
      end)
    end)
  end)
end

---Ask for the first unpair, then suggest an operation at the target line.
M.action.startlux_op = function() H.run_operation(false) end

---Like `startlux_op`, but execute the suggestion. If the window has no unpair,
---scroll one page forward with <C-F> instead.
M.action.startlux_apply = function() H.run_operation(true) end

---Drop the in-flight request.
M.action.startlux_cancel = function()
  if M.pending and M.pending.cancel then M.pending.cancel() end
  M.pending = nil
end

---Show the first-unpair request used by `startlux_op` and `startlux_apply`.
M.action.startlux_prompt = function()
  local first = math.max(1, fn.line("w0"))
  local last = math.max(1, fn.line("w$"))
  local body = H.build_payload(first, last)
  local ok, data = pcall(vim.json.decode, body)
  local lines = { "# :Interlaced startlux_op first-unpair request", "" }

  if not ok or type(data) ~= "table" then
    lines[#lines + 1] = body
  else
    lines[#lines + 1] = ("- model: `%s`"):format(tostring(data.model))
    lines[#lines + 1] = ("- think_mode: `%s`"):format(tostring(data.think_mode))
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## state"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "```text"
    vim.list_extend(lines, vim.split(tostring(data.state), "\n", { plain = true }))
    lines[#lines + 1] = "```"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## questions.first_unpair"
    lines[#lines + 1] = ""
    local question = type(data.questions) == "table" and data.questions.first_unpair or {}
    lines[#lines + 1] = ("> %s"):format(tostring(question.instructions or ""))
    lines[#lines + 1] = ""
    local criteria = type(question.criteria) == "table" and question.criteria or {}
    local keys = vim.tbl_keys(criteria)
    table.sort(keys, function(a, b)
      local na, nb = tonumber(a), tonumber(b)
      if na and nb then return na < nb end
      return tostring(a) < tostring(b)
    end)
    for _, key in ipairs(keys) do
      lines[#lines + 1] = ("- `%s` — %s"):format(tostring(key), tostring(criteria[key]))
    end
  end

  vim.cmd("botright new")
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
end

-- ---------------------------------------------------------------------------
-- subcommands
-- ---------------------------------------------------------------------------
-- The actions above are reachable as `:Interlaced startlux_op`,
-- `:Interlaced startlux_apply`, `:Interlaced startlux_cancel` and
-- `:Interlaced startlux_prompt`: `init.lua` adds this module to the providers
-- it dispatches to, and `config.keymaps` binds `gn` to `startlux_op`.
--
-- Requiring this module has no side effects beyond the highlight group, so it
-- still works standalone (`require "interlaced.startlux".action.startlux_op()`).

return M
