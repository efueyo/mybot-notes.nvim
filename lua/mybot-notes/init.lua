local M = {}

function M.setup(opts)
  local config = require("mybot-notes.config")
  config.setup(opts)

  local buffer = require("mybot-notes.buffer")
  local api = require("mybot-notes.api")
  local cache = require("mybot-notes.cache")

  -- User commands
  vim.api.nvim_create_user_command("NotesNew", function()
    buffer.create_new()
  end, { desc = "Create a new note" })

  vim.api.nvim_create_user_command("NotesDaily", function()
    api.daily(function(err, note)
      if err then
        vim.notify("Failed to get daily note: " .. err, vim.log.levels.ERROR)
        return
      end
      buffer.open(note)
    end)
  end, { desc = "Open today's daily note" })

  vim.api.nvim_create_user_command("NotesDelete", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local id = vim.b[bufnr].mynotes_id
    if not id then
      vim.notify("Not a saved note buffer", vim.log.levels.WARN)
      return
    end
    local title = vim.b[bufnr].mynotes_title or id
    local choice = vim.fn.confirm("Delete note: " .. title .. "?", "&Yes\n&No", 2)
    if choice ~= 1 then
      return
    end
    api.delete(id, function(err)
      if err then
        vim.notify("Failed to delete note: " .. err, vim.log.levels.ERROR)
        return
      end
      cache.remove(id)
      buffer.close(id)
      vim.notify("Note deleted", vim.log.levels.INFO)
    end)
  end, { desc = "Delete the current note" })

  vim.api.nvim_create_user_command("NotesSync", function()
    cache.sync(function()
      vim.notify("Notes synced", vim.log.levels.INFO)
    end)
  end, { desc = "Sync notes cache from server" })

  vim.api.nvim_create_user_command("NotesSearch", function()
    require("mybot-notes.telescope").search()
  end, { desc = "Search notes with Telescope" })

  vim.api.nvim_create_user_command("NotesTags", function()
    require("mybot-notes.telescope").tags()
  end, { desc = "Browse notes by tag with Telescope" })

  -- Global keymaps
  local keymaps = config.values.keymaps
  if keymaps.create and keymaps.create ~= "" and keymaps.create ~= false then
    vim.keymap.set("n", keymaps.create, "<cmd>NotesNew<cr>", { desc = "New note" })
  end
  if keymaps.search and keymaps.search ~= "" and keymaps.search ~= false then
    vim.keymap.set("n", keymaps.search, "<cmd>NotesSearch<cr>", { desc = "Search notes" })
  end
  if keymaps.daily and keymaps.daily ~= "" and keymaps.daily ~= false then
    vim.keymap.set("n", keymaps.daily, "<cmd>NotesDaily<cr>", { desc = "Daily note" })
  end
  if keymaps.tags and keymaps.tags ~= "" and keymaps.tags ~= false then
    vim.keymap.set("n", keymaps.tags, "<cmd>NotesTags<cr>", { desc = "Browse tags" })
  end

  -- Optional: nvim-cmp integration
  local cmp_ok, cmp = pcall(require, "cmp")
  if cmp_ok then
    cmp.register_source("mybot_notes", require("mybot-notes.cmp").new())
  end

  -- Optional: Telescope extension
  local telescope_ok, telescope = pcall(require, "telescope")
  if telescope_ok then
    telescope.load_extension("mybot_notes")
  end
end

return M
