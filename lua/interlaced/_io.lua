#!/usr/bin/env lua

local M = {}
---@param path string
---@return string|nil
M.read = function(path)
  local f = io.open(path, "r")
  if f == nil then
    vim.notify(string.format("Failed to open %s", path), vim.log.levels.ERROR)
    return
  end
  s = f:read("*a")
  f:close()
  return s
end

---@return boolean
M.write = function(path, s)
  local f = io.open(path, "w")
  if f == nil then
    vim.notify(string.format("Failed to write to %s", path), vim.log.levels.ERROR)
    return false
  end
  f:write(s)
  f:close()
  return true
end
return M
