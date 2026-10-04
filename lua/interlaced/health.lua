#!/usr/bin/env lua

local M = {}

M.check = function()
  vim.health.start("interlaced.nvim")

  if vim.fn.has("nvim-0.12") == 1 then
    vim.health.ok("Neovim >= 0.12")
  else
    vim.health.error("Neovim >= 0.12 is required")
  end

  local ok, config = pcall(require, "interlaced.config")
  if not ok then
    vim.health.error("interlaced.config could not be loaded: " .. tostring(config))
    return
  end

  if type(config.lang_num) == "number" and config.lang_num >= 1 then
    vim.health.ok(("lang_num = %d"):format(config.lang_num))
  else
    vim.health.error(("lang_num must be a positive integer, got %s"):format(vim.inspect(config.lang_num)))
  end

  local limit = config.undo_limit
  if limit == nil or limit <= 0 then
    vim.health.ok("undo_limit = unlimited")
  else
    vim.health.ok(("undo_limit = %d"):format(limit))
  end

  if type(config.keymaps) == "table" then
    vim.health.ok(("%d keymaps configured"):format(#config.keymaps))
  else
    vim.health.warn("keymaps is not a table; keybindings will not be enabled")
  end

  if type(config.language_separator) ~= "table" then
    vim.health.warn("language_separator is not a table")
  end

  if config.enable_keybindings_hook ~= nil and type(config.enable_keybindings_hook) ~= "function" then
    vim.health.warn("enable_keybindings_hook is not a function")
  end

  if config.disable_keybindings_hook ~= nil and type(config.disable_keybindings_hook) ~= "function" then
    vim.health.warn("disable_keybindings_hook is not a function")
  end
end

return M
