local M = {}

---@param opts? mybot.Config
function M.setup(opts)
  local config = require("mybot-notes.config")
  config.setup(opts)

  local buffer = require("mybot-notes.buffer")
  local api = require("mybot-notes.api")
  local cache = require("mybot-notes.cache")

  -- User commands
  vim.api.nvim_create_user_command("NotesNew", function()
    require("mybot-notes.telescope").template_picker()
  end, { desc = "Mybot Create a new note (pick template)" })

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

  vim.api.nvim_create_user_command("NotesMakeTemplate", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local id = vim.b[bufnr].mynotes_id
    if not id or vim.b[bufnr].mynotes_is_new then
      vim.notify("Save the note first before converting to a template", vim.log.levels.WARN)
      return
    end
    if vim.b[bufnr].mynotes_is_template then
      vim.notify("Already a template", vim.log.levels.WARN)
      return
    end
    local title = vim.b[bufnr].mynotes_title or id
    local choice = vim.fn.confirm("Convert to template: " .. title .. "?", "&Yes\n&No", 2)
    if choice ~= 1 then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")
    local extracted_title = buffer.extract_title(bufnr)
    api.make_template(id, extracted_title, content, function(err, note)
      if err then
        vim.notify("Failed to convert to template: " .. err, vim.log.levels.ERROR)
        return
      end
      vim.b[bufnr].mynotes_is_template = true
      vim.b[bufnr].mynotes_title = note.title
      vim.api.nvim_buf_set_name(bufnr, "mynotes://template/" .. id)
      vim.bo[bufnr].modified = false
      cache.remove(id)
      cache.upsert_template(note)
      cache.refresh_all(function()
        vim.notify("Note converted to template", vim.log.levels.INFO)
      end)
    end)
  end, { desc = "Mybot Convert current note to a template" })

  vim.api.nvim_create_user_command("NotesSync", function()
    cache.refresh_all(function()
      vim.notify("Notes synced", vim.log.levels.INFO)
    end)
  end, { desc = "Mybot Sync notes and templates cache from server" })

  vim.api.nvim_create_user_command("NotesToday", function(cmd_opts)
    local date = nil
    if cmd_opts.args and cmd_opts.args ~= "" then
      date = cmd_opts.args
    end
    require("mybot-notes.today").open(date)
  end, { nargs = "?", desc = "Mybot Open today dashboard" })

  vim.api.nvim_create_user_command("NotesSearch", function()
    require("mybot-notes.telescope").search()
  end, { desc = "Search notes with Telescope" })

  vim.api.nvim_create_user_command("NotesTags", function()
    require("mybot-notes.telescope").tags()
  end, { desc = "Browse notes by tag with Telescope" })

  -- Global keymaps
  local keymaps = config.values.keymaps
  if keymaps.create and keymaps.create ~= "" and keymaps.create ~= false then
    vim.keymap.set("n", keymaps.create, "<cmd>NotesNew<cr>", { desc = "Mybot New note" })
  end
  if keymaps.search and keymaps.search ~= "" and keymaps.search ~= false then
    vim.keymap.set("n", keymaps.search, "<cmd>NotesSearch<cr>", { desc = "Mybot Search notes" })
  end
  if keymaps.daily and keymaps.daily ~= "" and keymaps.daily ~= false then
    vim.keymap.set("n", keymaps.daily, "<cmd>NotesDaily<cr>", { desc = "Mybot Daily note" })
  end
  if keymaps.tags and keymaps.tags ~= "" and keymaps.tags ~= false then
    vim.keymap.set("n", keymaps.tags, "<cmd>NotesTags<cr>", { desc = "Mybot Browse tags" })
  end
  if keymaps.today and keymaps.today ~= "" and keymaps.today ~= false then
    vim.keymap.set("n", keymaps.today, "<cmd>NotesToday<cr>", { desc = "Mybot Today dashboard" })
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
