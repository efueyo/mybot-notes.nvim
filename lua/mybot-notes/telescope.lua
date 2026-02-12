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

  cache.ensure_fresh(function()
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
  end)
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

  cache.ensure_fresh(function()
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
  end)
end

return M
