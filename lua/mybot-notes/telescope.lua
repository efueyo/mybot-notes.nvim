local cache = require("mybot-notes.cache")
local buffer = require("mybot-notes.buffer")
local api = require("mybot-notes.api")

local M = {}

--- Build the entry_maker function for the notes picker.
local function make_entry(note)
  return {
    value = note,
    display = note.title or note.id,
    ordinal = (note.title or "") .. " " .. (note.content or ""),
  }
end

--- Get the list of notes for the picker, depending on tag filter.
---@param default_tag string|nil
---@return table[]
local function get_notes(default_tag)
  if default_tag then
    return cache.get_by_tag(default_tag)
  end
  return cache.search("")
end

--- Open the notes search picker.
--- If opts.default_tag is set, pre-filter notes by that tag.
---@param opts table|nil
function M.search(opts)
  opts = opts or {}

  local ok, _ = pcall(require, "telescope")
  if not ok then
    vim.notify("mybot-notes: telescope.nvim is required for search", vim.log.levels.ERROR)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local previewers = require("telescope.previewers")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local notes = get_notes(opts.default_tag)
  local prompt_title = opts.default_tag and ("Notes #" .. opts.default_tag) or "Notes"

  local function make_finder(results)
    return finders.new_table({
      results = results,
      entry_maker = make_entry,
    })
  end

  local function delete_selected(prompt_bufnr)
    local selection = action_state.get_selected_entry()
    if not selection then
      return
    end
    local note = selection.value
    local choice = vim.fn.confirm("Delete note: " .. (note.title or note.id) .. "?", "&Yes\n&No", 2)
    if choice ~= 1 then
      return
    end
    api.delete(note.id, function(err)
      if err then
        vim.notify("Failed to delete note: " .. err, vim.log.levels.ERROR)
        return
      end
      cache.remove(note.id)
      buffer.close(note.id)
      vim.notify("Note deleted", vim.log.levels.INFO)

      local current_picker = action_state.get_current_picker(prompt_bufnr)
      current_picker:refresh(make_finder(get_notes(opts.default_tag)))
    end)
  end

  pickers
    .new(opts, {
      prompt_title = prompt_title,
      finder = make_finder(notes),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = "Note Preview",
        define_preview = function(self, entry)
          local content = entry.value.content or ""
          local lines = vim.split(content, "\n", { plain = true })
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          vim.bo[self.state.bufnr].filetype = "markdown"
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            buffer.open(selection.value)
          end
        end)

        map("i", "<C-d>", function()
          delete_selected(prompt_bufnr)
        end)
        map("n", "<C-d>", function()
          delete_selected(prompt_bufnr)
        end)

        return true
      end,
    })
    :find()
end

--- Open the tag picker. Selecting a tag opens the search picker filtered by that tag.
---@param opts table|nil
function M.tags(opts)
  opts = opts or {}

  local ok, _ = pcall(require, "telescope")
  if not ok then
    vim.notify("mybot-notes: telescope.nvim is required for tags", vim.log.levels.ERROR)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local tags = cache.get_tags()

  pickers
    .new(opts, {
      prompt_title = "Tags",
      finder = finders.new_table({
        results = tags,
        entry_maker = function(tag)
          return {
            value = tag,
            display = "#" .. tag,
            ordinal = tag,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            M.search({ default_tag = selection.value })
          end
        end)
        return true
      end,
    })
    :find()
end

--- Sentinel id for the "Blank note" entry in the template picker.
local BLANK_ID = "__blank__"

--- Open the template picker for creating a new note.
--- Shows "Blank note" + all templates. If no templates exist, skips the picker.
--- Actions: <CR> create note, <C-e> edit template, <C-d> delete template.
---@param opts table|nil
function M.template_picker(opts)
  opts = opts or {}

  local ok, _ = pcall(require, "telescope")
  if not ok then
    vim.notify("mybot-notes: telescope.nvim is required", vim.log.levels.ERROR)
    return
  end

  cache.ensure_templates(function(templates)
    if #templates == 0 then
      buffer.create_new()
      return
    end

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local previewers = require("telescope.previewers")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local function build_entries(tmpls)
      local entries = { { id = BLANK_ID, title = "Blank note", content = "" } }
      for _, tmpl in ipairs(tmpls) do
        entries[#entries + 1] = tmpl
      end
      return entries
    end

    local function make_tmpl_finder(entries)
      return finders.new_table({
        results = entries,
        entry_maker = function(item)
          return {
            value = item,
            display = item.title or item.id,
            ordinal = item.title or "",
          }
        end,
      })
    end

    local function is_blank(entry)
      return entry and entry.value.id == BLANK_ID
    end

    local function create_from_template(prompt_bufnr)
      local selection = action_state.get_selected_entry()
      actions.close(prompt_bufnr)
      if not selection then
        return
      end
      if is_blank(selection) then
        buffer.create_new()
        return
      end
      api.resolve_template(selection.value.id, function(err, resolved)
        if err then
          vim.notify("Failed to resolve template: " .. err, vim.log.levels.ERROR)
          return
        end
        buffer.create_new(resolved.title, resolved.content)
      end)
    end

    local function edit_template(prompt_bufnr)
      local selection = action_state.get_selected_entry()
      if not selection or is_blank(selection) then
        return
      end
      local tmpl = selection.value
      local choice = vim.fn.confirm("Edit template: " .. (tmpl.title or tmpl.id) .. "?", "&Yes\n&No", 2)
      if choice ~= 1 then
        return
      end
      actions.close(prompt_bufnr)
      buffer.open_template(tmpl)
    end

    local function delete_template(prompt_bufnr)
      local selection = action_state.get_selected_entry()
      if not selection or is_blank(selection) then
        return
      end
      local tmpl = selection.value
      local choice = vim.fn.confirm("Delete template: " .. (tmpl.title or tmpl.id) .. "?", "&Yes\n&No", 2)
      if choice ~= 1 then
        return
      end
      api.delete_template(tmpl.id, function(err)
        if err then
          vim.notify("Failed to delete template: " .. err, vim.log.levels.ERROR)
          return
        end
        cache.remove_template(tmpl.id)
        vim.notify("Template deleted", vim.log.levels.INFO)

        local updated = cache.get_templates_cached()
        if #updated == 0 then
          if vim.api.nvim_buf_is_valid(prompt_bufnr) then
            actions.close(prompt_bufnr)
          end
          buffer.create_new()
          return
        end
        local current_picker = action_state.get_current_picker(prompt_bufnr)
        if current_picker then
          current_picker:refresh(make_tmpl_finder(build_entries(updated)))
        end
      end)
    end

    pickers
      .new(opts, {
        prompt_title = "New Note — Pick Template",
        finder = make_tmpl_finder(build_entries(templates)),
        sorter = conf.generic_sorter(opts),
        previewer = previewers.new_buffer_previewer({
          title = "Template Preview",
          define_preview = function(self, entry)
            if is_blank(entry) then
              vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "" })
              return
            end
            local content = entry.value.content or ""
            local lines = vim.split(content, "\n", { plain = true })
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
            vim.bo[self.state.bufnr].filetype = "markdown"
          end,
        }),
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            create_from_template(prompt_bufnr)
          end)

          map("i", "<C-e>", function()
            edit_template(prompt_bufnr)
          end)
          map("n", "<C-e>", function()
            edit_template(prompt_bufnr)
          end)

          map("i", "<C-d>", function()
            delete_template(prompt_bufnr)
          end)
          map("n", "<C-d>", function()
            delete_template(prompt_bufnr)
          end)

          return true
        end,
      })
      :find()
  end)
end

return M
