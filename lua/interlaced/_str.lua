#!/usr/bin/env lua

local M = {}
---@param s string
---@param prefix string
---@return string
M.removeprefix = function(s, prefix)
  local len = #prefix
  if s:sub(1, len) == prefix then
    return s:sub(len + 1)
  else
    return s
  end
end
return M
