---DeepSeek bridge client for interlaced.nvim.
---
---Sends to the local DeepSeek bridge service (see `deepseek/README.md`):
---
---1. the local prompt file (`p.md` by default),
---2. the lines currently visible in the window, and
---3. the cursor line with a `|` marking the cursor column,
---
---then renders whatever DeepSeek answers in a split window.
---
---This module is intentionally standalone: it keeps its own options, talks to
---the service with `vim.uv` (no `curl`, no shell), and does not import or modify
---any other `interlaced` module.
---
---Options are read from `vim.g.interlaced.deepseek` (or the flat
---`vim.g.interlaced_deepseek`), falling back to `M.config` below.
---
---Commands (registered on `require`):
---  :InterlacedDeepseek [extra instruction]
---  :InterlacedDeepseekStatus

local M = {
  _H = {},
  action = {},
}

---Defaults, overridable via `vim.g.interlaced.deepseek`.
M.config = {
  ---where the bridge service listens; must match `deepseek/server.mjs`
  host = "127.0.0.1",
  port = 8765,
  ---prompt file sent to DeepSeek; relative paths are looked up in the current
  ---working directory and then next to the current buffer
  prompt_file = "p.md",
  ---how to start the service when it is not running yet
  auto_start = true,
  node = "node",
  ---defaults to `<repo>/deepseek/server.mjs`
  server_script = nil,
  ---where `auto_start` sends the service's output; nil discards it
  log_file = nil,
  ---how long DeepSeek may take to answer
  timeout_ms = 300000,
  ---`botright split` for a window below, `botright vsplit` for one on the right
  split_command = "botright split",
  split_height_ratio = 0.35,
  split_width_ratio = 0.45,
  ---buffer-local key in the answer window that closes it
  close_keymap = "q",
}

local uv = vim.uv or vim.loop
local api = vim.api
local fn = vim.fn
local H = M._H

---In-flight request, or nil: `{ cancel = fun(), buf = integer }`
M.pending = nil

-- ---------------------------------------------------------------------------
-- options
-- ---------------------------------------------------------------------------

---@param key string
---@return any
local function opt(key)
  local nested = vim.g.interlaced
  if type(nested) == "table" and type(nested.deepseek) == "table" and nested.deepseek[key] ~= nil then
    return nested.deepseek[key]
  end
  local flat = vim.g.interlaced_deepseek
  if type(flat) == "table" and flat[key] ~= nil then
    return flat[key]
  end
  return M.config[key]
end

M.opt = opt

---Directory holding this plugin, i.e. `lua/interlaced/deepseek.lua` -> repo root.
---@return string
H.repo_root = function()
  local source = debug.getinfo(1, "S").source
  return fn.fnamemodify(source:sub(2), ":p:h:h:h")
end

-- ---------------------------------------------------------------------------
-- payload: prompt file + visible window + cursor line
-- ---------------------------------------------------------------------------

---@return string
H.prompt_file = function()
  local path = opt("prompt_file")
  if type(path) ~= "string" or path == "" then return "" end
  path = fn.expand(path)
  if path:match("^%a:[/\\]") or path:sub(1, 1) == "/" or path:sub(1, 1) == "~" then
    return path
  end
  local candidates = { vim.fs.joinpath(fn.getcwd(), path) }
  local buffer_dir = fn.expand("%:p:h")
  if buffer_dir ~= "" then
    candidates[#candidates + 1] = vim.fs.joinpath(buffer_dir, path)
  end
  for _, candidate in ipairs(candidates) do
    if fn.filereadable(candidate) == 1 then return candidate end
  end
  return candidates[1]
end

---@return { prompt: string, has_prompt: boolean, first: integer, last: integer, lnum: integer, col: integer }
H.context = function()
  local prompt = H.prompt_file()
  return {
    prompt = prompt,
    has_prompt = prompt ~= "" and fn.filereadable(prompt) == 1,
    first = math.max(1, fn.line("w0")),
    last = math.max(1, fn.line("w$")),
    lnum = fn.line("."),
    col = fn.col("."),
  }
end

---@param extra string|nil
---@return string
H.build_payload = function(extra)
  local lines = {}
  local context = H.context()

  if context.has_prompt then
    local handle = io.open(context.prompt, "r")
    if handle then
      for line in handle:lines() do lines[#lines + 1] = line end
      handle:close()
    end
  else
    lines[#lines + 1] = ("(prompt file not found: %s)"):format(context.prompt)
  end

  extra = type(extra) == "string" and vim.trim(extra) or ""
  if extra ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = extra
  end

  -- the two blocks below mirror the reference `redir!` snippet
  lines[#lines + 1] = "---"
  lines[#lines + 1] = "根据上面示例，对下面状态给出操作:"
  lines[#lines + 1] = "#### fetch_window result:"
  lines[#lines + 1] = "```"
  vim.list_extend(lines, api.nvim_buf_get_lines(0, context.first - 1, context.last, false))
  lines[#lines + 1] = "```"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "#### fetch_cursor_line result:"
  lines[#lines + 1] = "```"
  local cursor_line = fn.getline(".")
  local col = fn.col(".") - 1
  lines[#lines + 1] = fn.strpart(cursor_line, 0, col) .. "|" .. fn.strpart(cursor_line, col)
  lines[#lines + 1] = "```"

  return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- minimal HTTP/1.1 client on libuv (works with `Connection: close`)
-- ---------------------------------------------------------------------------

---@param kind string
---@param message string
---@return table
local function failure(kind, message)
  return { kind = kind, message = message }
end

---@param raw string
---@return table|nil, table|nil
H.parse_response = function(raw)
  if raw == "" then
    return nil, failure("empty", "the bridge closed the connection without answering")
  end
  local head, body = raw:match("^(.-)\r\n\r\n(.*)$")
  if not head then
    return nil, failure("protocol", "the bridge sent a malformed HTTP response")
  end
  local ok, data = pcall(vim.json.decode, body)
  if not ok or type(data) ~= "table" then
    local status = tonumber(head:match("^HTTP/%d%.%d%s+(%d+)")) or 0
    return nil, failure("protocol", ("the bridge sent unreadable data (HTTP %d)"):format(status))
  end
  return data
end

---@param method string
---@param path string
---@param body string|nil
---@param timeout_ms integer
---@param cb fun(err: table|nil, response: table|nil)
---@return fun() cancel
H.http = function(method, path, body, timeout_ms, cb)
  local host, port = opt("host"), opt("port")
  local tcp = uv.new_tcp()
  local chunks = {}
  local done = false
  local timer

  local function finish(err, response)
    if done then return end
    done = true
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    if not tcp:is_closing() then
      pcall(tcp.read_stop, tcp)
      tcp:close()
    end
    vim.schedule(function() cb(err, response) end)
  end

  timer = uv.new_timer()
  timer:start(timeout_ms, 0, function()
    finish(failure("timeout", ("no answer from the bridge at %s:%d within %.0fs"):format(host, port, timeout_ms / 1000)))
  end)

  tcp:connect(host, port, function(connect_err)
    if connect_err then
      return finish(failure("connect", connect_err))
    end

    local request = {
      ("%s %s HTTP/1.1"):format(method, path),
      ("Host: %s:%d"):format(host, port),
      "Accept: application/json",
      "Connection: close",
    }
    if body then
      request[#request + 1] = "Content-Type: application/json"
      request[#request + 1] = ("Content-Length: %d"):format(#body)
    end
    request[#request + 1] = ""
    request[#request + 1] = body or ""

    local sent, send_err = pcall(tcp.write, tcp, table.concat(request, "\r\n"))
    if not sent then
      return finish(failure("send", tostring(send_err)))
    end

    tcp:read_start(function(read_err, data)
      if read_err then
        return finish(failure("read", read_err))
      end
      if data then
        chunks[#chunks + 1] = data
      else
        local response, parse_err = H.parse_response(table.concat(chunks))
        finish(parse_err, response)
      end
    end)
  end)

  return function() finish(failure("cancelled", "request cancelled")) end
end

-- ---------------------------------------------------------------------------
-- service start-up + retrying request
-- ---------------------------------------------------------------------------

---@return boolean, string|nil
H.start_service = function()
  local script = opt("server_script") or vim.fs.joinpath(H.repo_root(), "deepseek", "server.mjs")
  if fn.filereadable(script) == 0 then
    return false, ("bridge script not found: %s"):format(script)
  end
  local node = opt("node")
  if fn.executable(node) == 0 then
    return false, ("`%s` is not executable; set vim.g.interlaced.deepseek.node"):format(node)
  end
  local null_device = fn.has("win32") == 1 and "NUL" or "/dev/null"
  local log_file = opt("log_file")
  local out = type(log_file) == "string" and log_file ~= "" and fn.expand(log_file) or null_device
  local cmd = { node, script, "--port", tostring(opt("port")) }
  local started, result = pcall(fn.jobstart, cmd, {
    detach = true,
    -- A detached child must not inherit the caller's stdout/stderr pipes:
    -- whatever spawned Neovim would then keep waiting for them to close.
    stdio = { null_device, out, out },
  })
  if not started or result == 0 or result == -1 then
    return false, ("failed to start `%s`"):format(table.concat(cmd, " "))
  end
  vim.notify(("interlaced.deepseek: started the bridge (%s)"):format(table.concat(cmd, " ")), vim.log.levels.INFO)
  return true
end

---@param opts table|nil `{ timeout_ms, max_attempts, retry_delay_ms, auto_start }`
---@param cb fun(err: table|nil, response: table|nil)
---@return fun() cancel
H.request = function(method, path, body, cb, opts)
  opts = opts or {}
  local attempts = 0
  local cancelled = false
  local cancel_current

  local function attempt()
    if cancelled then return end
    attempts = attempts + 1
    cancel_current = H.http(method, path, body, opts.timeout_ms or 10000, function(err, response)
      if cancelled then return end
      -- the service is probably just not up yet: start it and keep trying
      if err and err.kind == "connect" and attempts < (opts.max_attempts or 1) then
        if attempts == 1 and opts.auto_start then
          local ok, reason = H.start_service()
          if not ok then
            return cb(failure("connect", ("%s (%s)"):format(err.message, reason)), nil)
          end
        end
        vim.defer_fn(attempt, opts.retry_delay_ms or 300)
        return
      end
      cb(err, response)
    end)
  end

  attempt()

  return function()
    cancelled = true
    if cancel_current then cancel_current() end
  end
end

-- ---------------------------------------------------------------------------
-- the answer window
-- ---------------------------------------------------------------------------

---@return integer buf
H.open_split = function()
  local command = opt("split_command")
  vim.cmd(command)

  local buf = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(0, buf)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "markdown"

  vim.wo.wrap = true
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"
  vim.wo.list = false
  vim.wo.cursorline = false

  local vertical = command:find("vs") ~= nil or command:find("vertical") ~= nil
  if vertical then
    api.nvim_win_set_width(0, math.max(20, math.floor(vim.o.columns * opt("split_width_ratio"))))
  else
    api.nvim_win_set_height(0, math.max(4, math.floor(vim.o.lines * opt("split_height_ratio"))))
  end

  pcall(api.nvim_buf_set_name, buf, "deepseek://result")

  local win = api.nvim_get_current_win()
  vim.keymap.set("n", opt("close_keymap"), function()
    if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
  end, { buffer = buf, nowait = true, desc = "Close the DeepSeek answer" })

  return buf
end

---@param buf integer
---@param lines string[]
H.render = function(buf, lines)
  if not api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

---@param context table
---@return string[]
H.waiting_lines = function(context)
  return {
    "Asking DeepSeek…",
    "",
    ("prompt file : %s%s"):format(context.prompt, context.has_prompt and "" or "   (missing)"),
    ("window      : lines %d-%d"):format(context.first, context.last),
    ("cursor      : line %d, col %d"):format(context.lnum, context.col),
    "",
    ("The answer will replace this text. Press '%s' to close this window."):format(opt("close_keymap")),
  }
end

---@param text string
---@return string[]
H.to_lines = function(text)
  text = (text or ""):gsub("\r\n", "\n")
  if vim.trim(text) == "" then
    return { "(DeepSeek returned an empty answer)" }
  end
  return vim.split(text, "\n", { plain = true })
end

-- ---------------------------------------------------------------------------
-- actions
-- ---------------------------------------------------------------------------

---Ask DeepSeek about the current window and show the answer in a split window.
---@param a table|string|nil user-command args, or a plain extra instruction
M.action.ask = function(a)
  if M.pending then
    vim.notify("interlaced.deepseek: still waiting for the previous answer", vim.log.levels.WARN)
    return
  end

  local extra = ""
  if type(a) == "table" then
    extra = tostring(a.args or "")
  elseif type(a) == "string" then
    extra = a
  end

  -- capture the window and cursor before the split steals the focus
  local payload = H.build_payload(extra)
  local context = H.context()
  local buf = H.open_split()
  H.render(buf, H.waiting_lines(context))

  local timeout_ms = opt("timeout_ms")
  local body = vim.json.encode({ text = payload, timeout_ms = timeout_ms })

  local function done(err, response)
    M.pending = nil
    if err and err.kind == "cancelled" then return end

    if err then
      H.render(buf, H.to_lines(("DeepSeek bridge error: %s"):format(err.message)))
      vim.notify("interlaced.deepseek: " .. err.message, vim.log.levels.ERROR)
      return
    end

    if response.ok ~= true then
      local reason = tostring(response.error or "unknown error")
      H.render(buf, H.to_lines(("DeepSeek error: %s"):format(reason)))
      vim.notify("interlaced.deepseek: " .. reason, vim.log.levels.ERROR)
      return
    end

    H.render(buf, H.to_lines(tostring(response.result or "")))
  end

  M.pending = {
    buf = buf,
    cancel = H.request("POST", "/ask", body, done, {
      timeout_ms = timeout_ms + 30000,
      max_attempts = opt("auto_start") and 30 or 1,
      retry_delay_ms = 300,
      auto_start = opt("auto_start"),
    }),
  }
end

---Show whether the bridge service is up and which DeepSeek page is connected.
M.action.status = function()
  local host, port = opt("host"), opt("port")
  return H.request("GET", "/status", nil, function(err, response)
    if err then
      vim.notify(
        ("interlaced.deepseek: no bridge at %s:%d (%s)"):format(host, port, err.message),
        vim.log.levels.WARN
      )
      return
    end
    local pages = response.pages or {}
    if #pages == 0 then
      vim.notify(
        ("interlaced.deepseek: bridge is up at %s:%d, but no DeepSeek page is connected"):format(host, port),
        vim.log.levels.WARN
      )
    else
      vim.notify(
        ("interlaced.deepseek: bridge up at %s:%d, connected to %s"):format(host, port, pages[1]),
        vim.log.levels.INFO
      )
    end
  end, { timeout_ms = 5000, max_attempts = 1 })
end

---Abandon the request in flight, if any.
M.action.cancel = function()
  if not M.pending then return end
  local cancel = M.pending.cancel
  M.pending = nil
  if cancel then cancel() end
end

-- ---------------------------------------------------------------------------
-- commands
-- ---------------------------------------------------------------------------

api.nvim_create_user_command("InterlacedDeepseek", function(a)
  M.action.ask(a)
end, {
  nargs = "*",
  desc = "Ask DeepSeek about the prompt file and the current window; show the answer in a split",
})

api.nvim_create_user_command("InterlacedDeepseekStatus", function()
  M.action.status()
end, {
  desc = "Report whether the DeepSeek bridge service and the browser page are reachable",
})

return M
