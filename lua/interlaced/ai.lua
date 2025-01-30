#!/usr/bin/env lua

local M = {}

local uv = vim.uv or vim.loop
local logger = require("interlaced.logger")
local _io = require("interlaced._io")

local d = {
  messages = {
    {
      role = "system",
      content = _io.read("/home/usr/projects/interlaced.nvim/tmp.txt"),
    },
  },

  stream = false,
  -- tool_choice = "required",
  -- tool_choice = "none",
  -- tool_choice = vim.NIL,
  temperature = 0.3,
  top_p = 1,
  -- model = "gpt-4o-mini"
  model = "glm-4-flash"
  -- model = "glm-4"
  -- model = "llama3.2",
}

---@param prompt string
---@return string|nil # data path
M.dump_data = function(prompt)
  for i, t in vim.iter(d.messages):rev():enumerate() do
    if t.role == "user" then
      table.remove(d.messages, i)
    end
  end
  table.insert(d.messages, { role = "user", content = prompt })
  local json = vim.json.encode(d)
  local path = "/tmp/1.json"
  local file = io.open(path, "w")
  if not file then return nil end
  file:write(json)
  file:close()
  return path
end

M.get_response = function()
  local curr_lineno = vim.fn.line "." - 1

  local lines = { "第一组:", "```", }
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, curr_lineno - 1 - 3, curr_lineno - 1, false)) do
    if line ~= "" then
      table.insert(lines, line)
    end
  end
  table.insert(lines, "```")
  table.insert(lines, "")
  table.insert(lines, "第二组:")
  table.insert(lines, "```")
  for i, line in ipairs(vim.api.nvim_buf_get_lines(0, curr_lineno - 1, curr_lineno - 1 + 2 + 1, false)) do
    if line ~= "" then
      if i == 1 then line = "(光标) " .. line end
      table.insert(lines, line)
    end
  end
  table.insert(lines, "```")
  table.insert(lines, "")
  table.insert(lines, "第三组:")
  table.insert(lines, "```")
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, curr_lineno - 1 + 2 + 1 + 1, curr_lineno - 1 + 2 + 1 + 1 + 2 + 1, false)) do
    if line ~= "" then
      table.insert(lines, line)
    end
  end
  table.insert(lines, "```")
  -- vim.api.nvim_buf_get_lines(0, curr_lineno - 3, curr_lineno + 1 + 3 + 1, false)
  local prompt = table.concat(lines, "\n")

  local path = M.dump_data(prompt)
  if path == nil then
    return
  end

  -- local secret = os.getenv "OPENAI_API_KEY"
  -- local endpoint = os.getenv "OPENAI_API_BASE" .. "/chat/completions"
  local secret = os.getenv "ZHIPU_API_KEY"
  local endpoint = os.getenv "ZHIPU_API_BASE" .. "/chat/completions"
  local args = { "--no-buffer", "-X", "POST", endpoint, "-H",
    "Content-Type: application/json",
    "-H", "Authorization: Bearer " .. secret,
    "-H", "api-key: " .. secret,
    "-d", "@" .. path }

  -- local llama3.2 just ignores tool_choice
  -- https://github.com/ollama/ollama/issues/7778
  -- args = { "--no-buffer", "-X", "POST", "http://localhost:11434/api/chat", "-H", "Content-Type: application/json", "-d", "@" .. path }

  local handle, pid
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local stdout_data = ""
  local stderr_data = ""

  local on_exit = vim.schedule_wrap(function(code, signal)
    stdout:read_stop()
    stderr:read_stop()
    stdout:close()
    stderr:close()
    if handle and not handle:is_closing() then
      handle:close()
    end

    if stdout_data ~= "" then
      -- github azure api / chatanywhere
      local choice = vim.json.decode(stdout_data).choices[1]

      if choice.finish_reason ~= "tool_calls" then
        M.show_content_response(choice.message.content)
        return
      end

      local func_name = choice.message.tool_calls[1]["function"].name
      vim.print(func_name)
      require "interlaced.reposition".cmd[func_name]()

      -- local llama3.2
      -- vim.print(vim.json.decode(stdout_data).message.content.tool_calls[1]["function"].name)
    end

    if stderr_data ~= "" then
      vim.print(stderr_data)
    end
  end)

  handle, pid = uv.spawn("curl", {
    args = args,
    stdio = { nil, stdout, stderr },
    hide = true,
    detach = true,
  }, on_exit)

  uv.read_start(stdout, function(err, data)
    if err then
      print("Error reading stdout: " .. vim.inspect(err))
    end
    if data then
      stdout_data = data
    end
  end)

  uv.read_start(stderr, function(err, data)
    if err then
      logger.error("Error reading stderr: " .. vim.inspect(err))
    end
    if data then
      stderr_data = data
    end
  end)
end

---@param s string
M.show_content_response = function(s)
  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(s, "\n", { plain = true, trimempty = true }))
  vim.cmd "topleft split"
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].buftype = 'nowrite'
  vim.bo[bufnr].filetype = 'markdown'
end

return M
