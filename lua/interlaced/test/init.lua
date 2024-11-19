#!/usr/bin/env lua

local pkg_name = "interlaced"

local function dev_reload()
  for k, _ in pairs(package.loaded) do
    if k:match(pkg_name) then
      package.loaded[k] = nil
    end
  end
  require(pkg_name).setup({})
end

-- When in development mode, press `<leader>pr` to quickly reload your changes
vim.keymap.set({ "n" }, "<leader>it", dev_reload, { silent = true, desc = "Test plugin function" })
