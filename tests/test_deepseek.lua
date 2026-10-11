#!/usr/bin/env lua

-- Tests for `lua/interlaced/deepseek.lua`: the payload it builds, the HTTP
-- client framing, and the send round trip. The browser half is replaced by a
-- stub TCP server that speaks the same protocol as `deepseek/server.mjs`.
--
-- There is nothing to test about the answer: the module only pushes context to
-- DeepSeek and never reads the reply back.

local deepseek = require "interlaced.deepseek"
local H = deepseek._H
local uv = vim.uv or vim.loop

---@param window_expected string
---@param window_got string
local function check(name, expected, got)
  assert(expected == got,
    ("%s: expected\n%q\ngot\n%q"):format(name, expected, got))
end

---`handle:getsockname()` returns a table on newer luv, `ip, port` on older.
---@param handle table
---@return integer
local function local_port(handle)
  local first, second = handle:getsockname()
  if type(first) == "table" then return first.port end
  return second
end

-- ---------------------------------------------------------------------------
-- a stub bridge service
-- ---------------------------------------------------------------------------

local SEND_REPLY = '{"ok":true,"delivered":true,"bytes":4242,"page":"https://chat.deepseek.com/x","elapsed_ms":12}'
local STATUS_REPLY = '{"ok":true,"version":1,"pages":["https://chat.deepseek.com/x"],"busy":false}'
local NO_PAGE_REPLY = '{"ok":true,"version":1,"pages":[],"busy":false}'

local replies = { status = STATUS_REPLY }
local seen_requests = {}

local server = uv.new_tcp()
server:bind("127.0.0.1", 0)
server:listen(16, function()
  -- luv 1.52 wants the handle passed in: `accept()` alone returns EAGAIN
  local client = uv.new_tcp()
  local ok, accept_err = server:accept(client)
  if ok == nil or accept_err then return end
  local buffer = ""
  local answered = false
  client:read_start(function(err, data)
    if err or not data or answered then return end
    buffer = buffer .. data
    if not buffer:find("\r\n\r\n", 1, true) then return end
    answered = true
    seen_requests[#seen_requests + 1] = buffer

    local reply = buffer:match("^POST ") and SEND_REPLY or replies.status
    local response = table.concat({
      "HTTP/1.1 200 OK",
      "Content-Type: application/json",
      ("Content-Length: %d"):format(#reply),
      "Connection: close",
      "",
      reply,
    }, "\r\n")

    client:read_stop()
    client:write(response, function()
      client:shutdown(function() client:close() end)
    end)
  end)
end)

local port = local_port(server)

-- a port nothing listens on, to check that connecting fails fast
local probe = uv.new_tcp()
probe:bind("127.0.0.1", 0)
local dead_port = local_port(probe)
probe:close()

-- ---------------------------------------------------------------------------
-- notifications: the send-only module reports through `vim.notify`
-- ---------------------------------------------------------------------------

local notices = {}
vim.notify = function(msg, level)
  notices[#notices + 1] = { msg = tostring(msg), level = level }
end

---@return table|nil
local function last_notice() return notices[#notices] end

---@param from integer index of the first notice to look at
---@param level integer
---@return string|nil
local function notice_at(from, level)
  local notice = notices[from]
  if notice == nil or notice.level ~= level then return nil end
  return notice.msg
end

-- ---------------------------------------------------------------------------
-- wiring
-- ---------------------------------------------------------------------------

assert(vim.fn.exists(":InterlacedDeepseek") == 2, ":InterlacedDeepseek should be registered")
assert(vim.fn.exists(":InterlacedDeepseekStatus") == 2, ":InterlacedDeepseekStatus should be registered")
assert(H.repo_root() ~= "", "repo root should resolve")

-- `vim.g` hands back a copy, so the whole table is re-assigned on every change
local options = { port = port, auto_start = false }
local function set_options(patch)
  for key, value in pairs(patch or {}) do options[key] = value end
  vim.g.interlaced = { deepseek = vim.deepcopy(options) }
end

set_options()
assert(deepseek.opt("port") == port, "vim.g.interlaced.deepseek should win over the defaults")
assert(deepseek.opt("timeout_ms") == deepseek.config.timeout_ms, "unset keys should fall back to the defaults")

-- ---------------------------------------------------------------------------
-- payload
-- ---------------------------------------------------------------------------

local prompt_path = vim.fn.tempname() .. "-p.md"
vim.fn.writefile({ "# prompt", "keep the pairs aligned" }, prompt_path)
set_options { prompt_file = prompt_path }

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first line", "second line", "abcdef", "分号测试行" })
vim.api.nvim_win_set_cursor(0, { 3, 2 }) -- third line, third byte: between "b" and "c"

local context = H.context()
local payload = H.build_payload("be terse")

assert(payload:find("# prompt", 1, true), "payload should start with the prompt file")
assert(payload:find("keep the pairs aligned", 1, true), "payload should carry the whole prompt file")
assert(payload:find("be terse", 1, true), "payload should carry the extra instruction")
check("window block",
  table.concat(vim.api.nvim_buf_get_lines(0, context.first - 1, context.last, false), "\n"),
  payload:match("#### fetch_window result:\n```\n(.-)\n```"))
check("cursor block", "ab|cdef", payload:match("#### fetch_cursor_line result:\n```\n(.-)\n```"))

-- a missing prompt file is reported instead of blowing up
set_options { prompt_file = vim.fn.tempname() .. "-does-not-exist.md" }
assert(H.build_payload():find("prompt file not found", 1, true),
  "a missing prompt file should be reported")
set_options { prompt_file = prompt_path }

-- ---------------------------------------------------------------------------
-- client framing against the stub
-- ---------------------------------------------------------------------------

local status_response, status_err
H.http("GET", "/status", nil, 3000, function(err, response)
  status_err, status_response = err, response
end)
assert(vim.wait(3000, function() return status_response ~= nil or status_err ~= nil end), "GET /status timed out")
assert(status_err == nil, "GET /status failed: " .. tostring(status_err and status_err.message))
assert(status_response.ok == true, "unexpected /status reply")
assert(status_response.pages[1]:find("deepseek.com", 1, true) ~= nil, "/status should list the connected page")
assert(seen_requests[1]:find("Connection: close", 1, true), "the client should ask for a closed connection")

-- malformed input is reported, not thrown
local malformed = select(2, H.parse_response("HTTP/1.1 200 OK\r\n\r\nnot json"))
assert(malformed and malformed.kind == "protocol", "unreadable bodies should be reported")
local empty = select(2, H.parse_response(""))
assert(empty and empty.kind == "empty", "an empty response should be reported")

-- an unreachable service reports a connect error instead of hanging
set_options { port = dead_port }
local connect_err
H.http("GET", "/status", nil, 2000, function(err) connect_err = err end)
assert(vim.wait(3000, function() return connect_err ~= nil end), "connecting to a dead port should fail fast")
assert(connect_err.kind == "connect", "a dead port should be a connect error, got " .. tostring(connect_err.kind))
set_options { port = port }

-- ---------------------------------------------------------------------------
-- :InterlacedDeepseek — send, and nothing else
-- ---------------------------------------------------------------------------

local wins_before = #vim.api.nvim_list_wins()
deepseek.action.send("please answer")

assert(deepseek.pending ~= nil, "send should leave a request in flight")
assert(#vim.api.nvim_list_wins() == wins_before, "send must not open a window")

local sent_from = #notices + 1
assert(vim.wait(4000, function() return notice_at(sent_from, vim.log.levels.INFO) ~= nil end),
  "a successful send should be reported with vim.notify")
local sent_notice = notice_at(sent_from, vim.log.levels.INFO)
assert(deepseek.pending == nil, "no request should be left in flight once the send is confirmed")
assert(sent_notice:find("4242 bytes", 1, true), "the notice should report the size the bridge confirmed")
assert(sent_notice:find("chat.deepseek.com", 1, true), "the notice should name the page that got the text")

local posted = seen_requests[#seen_requests]
assert(posted:match("^POST /send"), "the round trip should POST to /send")
assert(posted:find("#### fetch_window result:", 1, true), "the POST body should carry the window block")
assert(posted:find("#### fetch_cursor_line result:", 1, true), "the POST body should carry the cursor block")
assert(posted:find("# prompt", 1, true), "the POST body should carry the prompt file")
assert(posted:find("please answer", 1, true), "the POST body should carry the extra instruction")
assert(posted:find(('"timeout_ms":%d'):format(deepseek.config.timeout_ms)) ~= nil,
  "the POST body should carry the configured timeout")

-- a request in flight blocks a second one instead of racing it
deepseek.pending = { cancel = function() end }
local blocked_from = #notices + 1
deepseek.action.send()
assert(notice_at(blocked_from, vim.log.levels.WARN) ~= nil, "a second send should warn")

-- ...and `cancel` drops it
deepseek.action.cancel()
assert(deepseek.pending == nil, "cancel should clear the in-flight send")

-- a bridge that cannot be reached is reported, not thrown
set_options { port = dead_port }
local failure_from = #notices + 1
deepseek.action.send()
assert(vim.wait(4000, function() return notice_at(failure_from, vim.log.levels.ERROR) ~= nil end),
  "a failed send should be reported")
assert(deepseek.pending == nil, "a failed send should not stay pending")
set_options { port = port }

-- ---------------------------------------------------------------------------
-- :InterlacedDeepseekStatus
-- ---------------------------------------------------------------------------

local ok_from = #notices + 1
deepseek.action.status()
assert(vim.wait(4000, function() return notice_at(ok_from, vim.log.levels.INFO) ~= nil end),
  "status should report the connected page")
assert(notice_at(ok_from, vim.log.levels.INFO):find("chat.deepseek.com", 1, true),
  "status should list the connected page url")

replies.status = NO_PAGE_REPLY
local empty_from = #notices + 1
deepseek.action.status()
assert(vim.wait(4000, function() return notice_at(empty_from, vim.log.levels.WARN) ~= nil end),
  "status should warn when no page is connected")
assert(notice_at(empty_from, vim.log.levels.WARN):find("no DeepSeek page is connected", 1, true),
  "the warning should say what is missing")

server:close()

print "all deepseek tests passed"
