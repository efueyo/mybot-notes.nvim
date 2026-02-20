local config = require("mybot-notes.config")

local M = {}

---@type mybot.CacheState
local state = {
  notes = {},
  notes_by_id = {},
  notes_by_title = {},
  tags = {},
  last_synced_at = 0,
  loaded = false,
  syncing = false,
  -- Template state
  templates = {},
  templates_last_synced_at = 0,
  templates_syncing = false,
}

--- Get the path to the cache file on disk.
---@return string
local function cache_path()
  return config.values.cache_dir .. "/cache.json"
end

--- Rebuild in-memory indexes from state.notes.
function M.rebuild_indexes()
  state.notes_by_id = {}
  state.notes_by_title = {}

  local tag_set = {}
  for _, note in ipairs(state.notes) do
    state.notes_by_id[note.id] = note
    if note.title then
      state.notes_by_title[note.title:lower()] = note
    end
    if note.tags then
      for _, tag in ipairs(note.tags) do
        tag_set[tag:lower()] = true
      end
    end
  end

  local sorted_tags = {}
  for tag in pairs(tag_set) do
    sorted_tags[#sorted_tags + 1] = tag
  end
  table.sort(sorted_tags)
  state.tags = sorted_tags
end

--- Load cache from disk (once). Does not trigger any syncs.
local function load_from_disk()
  if state.loaded then
    return
  end
  state.loaded = true

  local path = cache_path()
  if vim.fn.filereadable(path) == 1 then
    local lines = vim.fn.readfile(path)
    if #lines > 0 then
      local raw = table.concat(lines, "\n")
      local ok, data = pcall(vim.json.decode, raw)
      if ok and type(data) == "table" then
        state.notes = data.notes or {}
        state.last_synced_at = data.last_synced_at or 0
        state.templates = data.templates or {}
        state.templates_last_synced_at = data.templates_last_synced_at or 0
        M.rebuild_indexes()
      else
        vim.notify("mybot-notes: cache file corrupted, starting fresh", vim.log.levels.WARN)
      end
    end
  end
end

--- Load notes from cache, trigger background sync if stale.
function M.load()
  load_from_disk()

  if M.is_stale() and not state.syncing then
    state.syncing = true
    M.sync(function()
      state.syncing = false
    end)
  end
end

--- Persist in-memory state to disk.
function M.persist()
  local dir = config.values.cache_dir
  vim.fn.mkdir(dir, "p")

  local data = {
    notes = state.notes,
    last_synced_at = state.last_synced_at,
    templates = state.templates,
    templates_last_synced_at = state.templates_last_synced_at,
  }
  vim.fn.writefile({ vim.json.encode(data) }, cache_path())
end

--- Update or insert a single note in the cache.
---@param note mybot.Note
function M.upsert(note)
  local found = false
  for i, n in ipairs(state.notes) do
    if n.id == note.id then
      state.notes[i] = note
      found = true
      break
    end
  end
  if not found then
    state.notes[#state.notes + 1] = note
  end
  M.rebuild_indexes()
  M.persist()
end

--- Remove a note from cache by id.
---@param id string
function M.remove(id)
  local new_notes = {}
  for _, n in ipairs(state.notes) do
    if n.id ~= id then
      new_notes[#new_notes + 1] = n
    end
  end
  state.notes = new_notes
  M.rebuild_indexes()
  M.persist()
end

--- Return true if the notes cache is stale (TTL expired).
---@return boolean
function M.is_stale()
  return state.last_synced_at + config.values.cache_ttl < os.time()
end

--- Full sync: fetch all notes from API, replace cache, rebuild indexes, persist.
---@param callback? fun()
function M.sync(callback)
  local api = require("mybot-notes.api")
  api.get_all(function(err, notes)
    if err then
      vim.notify("mybot-notes: sync failed: " .. err, vim.log.levels.WARN)
      if callback then
        callback()
      end
      return
    end
    state.notes = notes
    state.last_synced_at = os.time()
    M.rebuild_indexes()
    M.persist()
    if callback then
      callback()
    end
  end)
end

-- Template methods

--- Return true if the template cache is stale.
---@return boolean
local function is_templates_stale()
  return state.templates_last_synced_at + config.values.cache_ttl < os.time()
end

--- Sync templates from server.
---@param callback? fun()
function M.sync_templates(callback)
  local api = require("mybot-notes.api")
  api.get_templates(function(err, templates)
    if err then
      vim.notify("mybot-notes: template sync failed: " .. err, vim.log.levels.WARN)
      if callback then
        callback()
      end
      return
    end
    state.templates = templates
    state.templates_last_synced_at = os.time()
    M.persist()
    if callback then
      callback()
    end
  end)
end

--- Ensure templates are loaded and fresh, then call callback with the list.
--- If cached and fresh, calls back synchronously via vim.schedule.
--- If stale, fetches from API first.
---@param callback fun(templates: mybot.Template[])
function M.ensure_templates(callback)
  load_from_disk()
  if not is_templates_stale() then
    vim.schedule(function()
      callback(state.templates)
    end)
    return
  end
  if state.templates_syncing then
    vim.schedule(function()
      callback(state.templates)
    end)
    return
  end
  state.templates_syncing = true
  M.sync_templates(function()
    state.templates_syncing = false
    callback(state.templates)
  end)
end

--- Update or insert a single template in the cache.
---@param template mybot.Template
function M.upsert_template(template)
  local found = false
  for i, t in ipairs(state.templates) do
    if t.id == template.id then
      state.templates[i] = template
      found = true
      break
    end
  end
  if not found then
    state.templates[#state.templates + 1] = template
  end
  M.persist()
end

--- Remove a template from cache by id.
---@param id string
function M.remove_template(id)
  local new_templates = {}
  for _, t in ipairs(state.templates) do
    if t.id ~= id then
      new_templates[#new_templates + 1] = t
    end
  end
  state.templates = new_templates
  M.persist()
end

--- Return the current cached templates list (no sync, no disk load).
---@return mybot.Template[]
function M.get_templates_cached()
  return state.templates
end

--- Refresh both notes and templates from server.
---@param callback? fun()
function M.refresh_all(callback)
  local remaining = 2
  local function check_done()
    remaining = remaining - 1
    if remaining == 0 and callback then
      callback()
    end
  end
  M.sync(check_done)
  M.sync_templates(check_done)
end

--- Search notes locally. Case-insensitive substring match on title and content.
--- Returns matching notes, title matches sorted first.
---@param query string
---@return mybot.Note[]
function M.search(query)
  M.load()
  local q = query:lower()
  local title_matches = {}
  local content_matches = {}

  for _, note in ipairs(state.notes) do
    local title_lower = (note.title or ""):lower()
    local content_lower = (note.content or ""):lower()
    if title_lower:find(q, 1, true) then
      title_matches[#title_matches + 1] = note
    elseif content_lower:find(q, 1, true) then
      content_matches[#content_matches + 1] = note
    end
  end

  -- Title matches first, then content-only matches
  for _, note in ipairs(content_matches) do
    title_matches[#title_matches + 1] = note
  end
  return title_matches
end

--- Return sorted list of unique tags across all cached notes.
---@return string[]
function M.get_tags()
  M.load()
  return state.tags
end

--- Return notes that have the given tag (case-insensitive match).
---@param tag string
---@return mybot.Note[]
function M.get_by_tag(tag)
  M.load()
  local t = tag:lower()
  local results = {}
  for _, note in ipairs(state.notes) do
    if note.tags then
      for _, note_tag in ipairs(note.tags) do
        if note_tag:lower() == t then
          results[#results + 1] = note
          break
        end
      end
    end
  end
  return results
end

--- Find a note by title (case-insensitive exact match).
---@param title string
---@return mybot.Note|nil
function M.find_by_title(title)
  M.load()
  return state.notes_by_title[title:lower()]
end

--- Find a note by id.
---@param id string
---@return mybot.Note|nil
function M.find_by_id(id)
  M.load()
  return state.notes_by_id[id]
end

--- Return list of {id, title} for all cached notes (used by cmp source).
---@return mybot.NoteTitle[]
function M.get_titles()
  M.load()
  local result = {}
  for _, note in ipairs(state.notes) do
    result[#result + 1] = { id = note.id, title = note.title }
  end
  return result
end

return M
