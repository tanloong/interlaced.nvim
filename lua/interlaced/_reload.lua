#!/usr/bin/env lua

local pkg_name = "interlaced"

local function dev_reload()
  require(pkg_name)._showing_chunknr = true
  require(pkg_name).cmd.ToggleChunkNr()

  for k, _ in pairs(package.loaded) do
    if k:sub(1, #pkg_name) == pkg_name then
      package.loaded[k] = nil
    end
  end
  require(pkg_name).setup({})
  vim.print(pkg_name .. " restarted at " .. os.date("%H:%M:%S"))
end

-- When in development mode, press `<leader>pr` to quickly reload your changes
vim.keymap.set({ "n" }, "<leader>it", dev_reload, { silent = true, desc = "Test plugin function" })
