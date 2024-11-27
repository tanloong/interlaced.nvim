#!/usr/bin/env lua

local M = {}

--- Example:
--- Input: {
---   foo = { id = 1000, group = "Search", priority = 10 },
---   bar = { id = 2000, group = "Comment", priority = 5 }
--- }
--- Output: {
---   { pattern = "foo", id = 1000, group = "Search", priority = 10 },
---   { pattern = "bar", id = 2000, group = "Comment", priority = 5 }
--- }
--- @param dict table<string, table> A table where keys are pattern names and values are tables containing associated properties.
--- @return table[] A list of tables, each containing a 'pattern' and its corresponding properties.
M.match_dict2list = function(dict)
  local ret = {}
  for pat, id_grp_prio in pairs(dict) do
    table.insert(ret, {pattern = pat, id = id_grp_prio.id, group = id_grp_prio.group, priority = id_grp_prio.priority})
  end
  return ret
end

--- Example:
--- Input: {
---   { pattern = "foo", id = 1000, group = "Search", priority = 10 },
---   { pattern = "bar", id = 2000, group = "Comment", priority = 5 }
--- }
--- Output: {
---   foo = { id = 1000, group = "Search", priority = 10 },
---   bar = { id = 2000, group = "Comment", priority = 5 }
--- }
---
--- @param list table[]
--- @return table
M.match_list2dict = function(list)
  local ret = {}
  for _, entry in ipairs(list) do
    local pattern = entry.pattern
    ret[pattern] = { id = entry.id, group = entry.group, priority = entry.priority }
  end
  return ret
end

return M
