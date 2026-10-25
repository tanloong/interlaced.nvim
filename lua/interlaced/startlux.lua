---StartLux Decision client for interlaced.nvim.
---
---`:Interlaced startlux` looks at the window, asks the StartLux Decision API
---(POST `/v1/decisions`) for the **first unaligned pair**, then
---
---1. puts the cursor on that pair, and
---2. flashes the pair for `highlight_ms` so it is easy to spot.
---
---The question asked is deliberately tiny: the payload contains the visible
---window with absolute line numbers, and the only question is "which chunk is
---the first one whose Chinese and English do not match". Because a misaligned
---chunk shifts every later chunk by one, the first mismatch is the only one
---worth locating.
---
---Options are read from `vim.g.interlaced.startlux` (or the flat
---`vim.g.interlaced_startlux`), falling back to `M.config` below.
---
---Subcommands (`init.lua` adds this module to the `:Interlaced` dispatcher and
---`config.keymaps` binds `gn` to `startlux`):
---  :Interlaced startlux          ask, jump, flash
---  :Interlaced startlux_cancel   drop the in-flight request
---  :Interlaced startlux_prompt   show the exact request that would be sent
---
---Nothing here touches the rest of the plugin: the module only reads the
---window and moves the cursor.

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

---The JSON body sent to POST `/v1/decisions`.
---@param first integer
---@param last integer
---@return string
H.build_payload = function(first, last)
  local blocks = H.blocks(first, last)
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
H.reveal = function(block)
  local win = api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  local ns = api.nvim_create_namespace("interlaced.startlux")
  local last = api.nvim_buf_line_count(buf)
  local start = math.min(math.max(block.start, 1), last)
  local stop = math.min(math.max(block.stop, start), last)

  pcall(api.nvim_win_set_cursor, win, { start, 0 })
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

---Ask StartLux for the first unaligned chunk, jump to it and flash it.
M.action.startlux = function()
  if M.pending then
    vim.notify("interlaced.startlux: the previous request is still running", vim.log.levels.WARN)
    return
  end

  local first = math.max(1, fn.line("w0"))
  local last = math.max(1, fn.line("w$"))
  local blocks = H.blocks(first, last)
  if #blocks < 2 then
    vim.notify("interlaced.startlux: the window has nothing to compare", vim.log.levels.WARN)
    return
  end

  local body = H.build_payload(first, last)

  local started = uv.hrtime()
  local entry = { cancel = function() end }
  M.pending = entry
  entry.cancel = H.post(body, function(err, text)
    M.pending = nil
    local elapsed = (uv.hrtime() - started) / 1e6

    if err then
      vim.notify("interlaced.startlux: " .. err, vim.log.levels.ERROR)
      return
    end

    local lnum, message = H.parse_answer(text or "")
    if not lnum then
      vim.notify("interlaced.startlux: " .. tostring(message), vim.log.levels.ERROR)
      return
    end

    if lnum == "none" then
      vim.notify(("interlaced.startlux: no unaligned chunk in this window (%.0f ms)"):format(elapsed), vim.log.levels.INFO)
      return
    end

    local block = H.block_at(lnum, blocks, first, last)
    H.reveal(block)
    vim.notify(("interlaced.startlux: first unpair at line %d (%.0f ms)"):format(block.start, elapsed), vim.log.levels.INFO)
  end)
end

---Drop the in-flight request.
M.action.startlux_cancel = function()
  if M.pending and M.pending.cancel then M.pending.cancel() end
  M.pending = nil
end

---Show the request that `:Interlaced startlux` would send.
M.action.startlux_prompt = function()
  local first = math.max(1, fn.line("w0"))
  local last = math.max(1, fn.line("w$"))
  local body = H.build_payload(first, last)
  local ok, data = pcall(vim.json.decode, body)
  local lines = { "# :Interlaced startlux request", "" }

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
-- The actions above are reachable as `:Interlaced startlux`,
-- `:Interlaced startlux_cancel` and `:Interlaced startlux_prompt`: `init.lua`
-- adds this module to the providers it dispatches to, and `config.keymaps`
-- binds `gn` to `startlux`.
--
-- Requiring this module has no side effects beyond the highlight group, so it
-- still works standalone (`require "interlaced.startlux".action.startlux()`).

return M
