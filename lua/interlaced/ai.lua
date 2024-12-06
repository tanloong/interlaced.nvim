#!/usr/bin/env lua

local M = {}

local uv = vim.uv or vim.loop
local logger = require("interlaced.logger")

local d = {
  messages = {
    {
      role = "system",
      -- content = "There is a text pair containing an array of sentences in different languages separated by a newline. The pair is taken from a sequence of many other pairs, and I will give you adjacent pairs above and below the target one, forming 3 pairs in total, separated from each other by an empty line.\nThe cursor is on the first line of the middle pair and we'll call that line \"current line\". The number and order of languages across each pair is the same, and a line from another pair is \"counterpart\" of current line if it is at the same position as current line in its own pair.\nYour goal is to determine whether the middle pair is semantically aligned across languages and choose ONE function to be called against CURRENT LINE."
      content = [[
I will give you 3 text pairs: above, middle, and below. Each pair has 2 lines, one in Chinese and the other in English.

The cursor is on the first line (or "current line") of the middle pair. The number and order of languages across each pair is the same, a line is "counterpart" of current line if they are at the same position as current line but in another pair. A pair is "aligned" if its Chinese line look like a translation to its English line. By "look like translation" I mean two texts from different languages conveys generally, but not necessarily exact, the same meaning, because some translation are libral translation instead of literal translation.

Your goal is to determine whether each pair is semantically aligned across languages and choose function from the `tools` to be called.
]]
    },
  },

  stream = false,
  tools = {
    {
      type = "function",
      ["function"] = {
        name = "PushUp",
        description =
        [[This function is called when both the above pairs is not aligned, and the "current line" is aligned with the ending part of the above pair's another line. Push current line up to the pair above, joining to the end of its counterpart.]],
        parameters = { ["type"] = "object", properties = vim.empty_dict() },
      }
    },
    {
      type = "function",
      ["function"] = {
        name = "NavigateUp",
        description =
        [[This function is called when both the above and middle pairs are not semantically aligned AND it can not be fixed by `PushUp` the "current line". Move cursor to the pair above at the counterpart of current line.]],
        parameters = { ["type"] = "object", properties = vim.empty_dict() },
      }
    },
    {
      type = "function",
      ["function"] = {
        name = "PullBelow",
        description =
        [[This function is called when the above pair is aligned but the middle and below pairs are not. Pull the counterpart line from the pair below up to the end of current line.]],
        parameters = { ["type"] = "object", properties = vim.empty_dict() },
      }
    },
    {
      type = "function",
      ["function"] = {
        name = "NavigateDown",
        description =
        [[This function is called when the both the above and middle pairs are semantically aligned across languages. Move cursor to the pair below at the counterpart of current line.]],
        parameters = { ["type"] = "object", properties = vim.empty_dict() },
      }
    },

  },
  -- tool_choice = "required",
  tool_choice = "none",
  -- tool_choice = vim.NIL,
  temperature = 1,
  top_p = 1,
  max_tokens = 1000,
  model = "gpt-4o-mini"
  -- model = "glm-4-plus"
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

  local lines = { "ABOVE:", "```", }
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, curr_lineno - 1 - 3, curr_lineno - 1, false)) do
    if line ~= "" then
      table.insert(lines, line)
    end
  end
  table.insert(lines, "```")
  table.insert(lines, "")
  table.insert(lines, "MIDDLE:")
  table.insert(lines, "```")
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, curr_lineno - 1, curr_lineno - 1 + 2 + 1, false)) do
    if line ~= "" then
      table.insert(lines, line)
      table.insert(lines, "")
    end
  end
  table.insert(lines, "```")
  table.insert(lines, "")
  table.insert(lines, "BELOW:")
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

  local secret = os.getenv "OPENAI_API_KEY"
  local endpoint = os.getenv "OPENAI_API_BASE" .. "/chat/completions"
  -- local endpoint = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
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
