#!/usr/bin/env lua

local M = {}

---@param msg string # message to log
---@param kind string # hl group to use for logging
---@param history boolean # whether to add the message to history
M._log = function(msg, kind, history)
  vim.schedule(function()
    vim.api.nvim_echo({
      { "Interlaced: " .. msg, kind },
    }, history, {})
  end)
end

-- nicer error messages using nvim_echo
---@param msg string # error message
M.error = function(msg)
  M._log(msg, "ErrorMsg", true)
end

-- nicer warning messages using nvim_echo
---@param msg string # warning message
M.warning = function(msg)
  M._log(msg, "WarningMsg", true)
end

-- nicer plain messages using nvim_echo
---@param msg string # plain message
M.info = function(msg)
  M._log(msg, "Normal", true)
end

return M
