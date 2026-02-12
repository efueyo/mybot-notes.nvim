local config = require("mybot-notes.config")

local M = {}

local state = {
  notes = {},
  notes_by_id = {},
  notes_by_title = {},
  tags = {},
  last_synced_at = 0,
  loaded = false,
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

--- Load cache from disk into memory. No-op if already loaded.
function M.load()
  if state.loaded then
    return
  end
  state.loaded = true

  local path = cache_path()
  if vim.fn.filereadable(path) ~= 1 then
    return
  end

  local lines = vim.fn.readfile(path)
  if #lines == 0 then
    return
  end

  local raw = table.concat(lines, "\n")
  local ok, data = pcall(vim.json.decode, raw)
  if not ok or type(data) ~= "table" then
    vim.notify("mybot-notes: cache file corrupted, starting fresh", vim.log.levels.WARN)
    return
  end

  state.notes = data.notes or {}
  state.last_synced_at = data.last_synced_at or 0
  M.rebuild_indexes()
end

--- Persist in-memory state to disk.
function M.persist()
  local dir = config.values.cache_dir
  vim.fn.mkdir(dir, "p")

  local data = {
    notes = state.notes,
    last_synced_at = state.last_synced_at,
  }
  vim.fn.writefile({ vim.json.encode(data) }, cache_path())
end

--- Update or insert a single note in the cache.
---@param note table
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

--- Return true if the cache is stale (TTL expired).
---@return boolean
function M.is_stale()
  return state.last_synced_at + config.values.cache_ttl < os.time()
end

--- Full sync: fetch all notes from API, replace cache, rebuild indexes, persist.
---@param callback function called when sync is complete
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

--- If stale, sync first then call callback. Otherwise call callback immediately.
--- This is the main entry point for read operations.
---@param callback function
function M.ensure_fresh(callback)
  M.load()
  if M.is_stale() then
    M.sync(callback)
  else
    if callback then
      callback()
    end
  end
end

--- Search notes locally. Case-insensitive substring match on title and content.
--- Returns matching notes, title matches sorted first.
---@param query string
---@return table[]
function M.search(query)
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
  return state.tags
end

--- Return notes that have the given tag (case-insensitive match).
---@param tag string
---@return table[]
function M.get_by_tag(tag)
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
---@return table|nil
function M.find_by_title(title)
  return state.notes_by_title[title:lower()]
end

--- Find a note by id.
---@param id string
---@return table|nil
function M.find_by_id(id)
  return state.notes_by_id[id]
end

--- Return list of {id, title} for all cached notes (used by cmp source).
---@return table[]
function M.get_titles()
  local result = {}
  for _, note in ipairs(state.notes) do
    result[#result + 1] = { id = note.id, title = note.title }
  end
  return result
end

return M
