local M = {}

--- Find an existing buffer by name.
---@param name string
---@return number|nil bufnr or nil
local function find_buf_by_name(name)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == name then
      return bufnr
    end
  end
  return nil
end

--- Set standard buffer options for a note buffer.
---@param bufnr number
local function set_buf_options(bufnr)
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].swapfile = false
end

--- Register BufWriteCmd autocmd for a note buffer.
---@param bufnr number
local function register_write_autocmd(bufnr)
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      M.save(bufnr)
    end,
  })
end

--- Extract title from buffer content.
--- 1. Scan first 5 lines for markdown heading (^#+ (.+))
--- 2. If not found, use first non-empty line (truncated to 60 chars)
--- 3. If buffer is empty, use "Quick note — <date>" format
---@param bufnr number
---@return string
function M.extract_title(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 5, false)

  -- Look for markdown heading in first 5 lines
  for _, line in ipairs(lines) do
    local heading = line:match("^#+ (.+)")
    if heading then
      return vim.trim(heading)
    end
  end

  -- Fallback: first non-empty line, truncated to 60 chars
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(all_lines) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" then
      if #trimmed > 60 then
        return trimmed:sub(1, 60)
      end
      return trimmed
    end
  end

  -- Buffer is empty
  return "Quick note — " .. os.date("%Y-%m-%d")
end

--- Open an existing note in a buffer.
--- If a buffer with mynotes://{id} already exists, switch to it.
--- Otherwise create a new buffer, populate with note.content, set metadata.
---@param note table
function M.open(note)
  local name = "mynotes://" .. note.id

  -- Check for existing buffer
  local existing = find_buf_by_name(name)
  if existing then
    vim.api.nvim_set_current_buf(existing)
    return
  end

  -- Create new buffer
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, name)

  -- Populate content
  local lines = vim.split(note.content or "", "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Set metadata
  vim.b[bufnr].mynotes_id = note.id
  vim.b[bufnr].mynotes_title = note.title
  vim.b[bufnr].mynotes_is_new = false

  -- Set buffer options and autocmd
  set_buf_options(bufnr)
  register_write_autocmd(bufnr)

  -- Switch to the buffer
  vim.api.nvim_set_current_buf(bufnr)
end

--- Create a new empty note buffer.
--- Optional title: pre-populate with "# <title>\n\n" if provided.
---@param title string|nil
function M.create_new(title)
  local name = "mynotes://new-" .. os.time()
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, name)

  -- Pre-populate with title if provided
  if title and title ~= "" then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "# " .. title, "", "" })
  end

  -- Set metadata
  vim.b[bufnr].mynotes_is_new = true

  -- Set buffer options and autocmd
  set_buf_options(bufnr)
  register_write_autocmd(bufnr)

  -- Switch to the buffer
  vim.api.nvim_set_current_buf(bufnr)
end

--- BufWriteCmd handler — called on :w in a note buffer.
---@param bufnr number
function M.save(bufnr)
  local api = require("mybot-notes.api")
  local cache = require("mybot-notes.cache")

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")
  local title = M.extract_title(bufnr)

  if vim.b[bufnr].mynotes_is_new then
    api.create(title, content, function(err, note)
      if err then
        vim.notify("Failed to create note: " .. err, vim.log.levels.ERROR)
        return
      end
      vim.b[bufnr].mynotes_id = note.id
      vim.b[bufnr].mynotes_title = note.title
      vim.b[bufnr].mynotes_is_new = false
      vim.api.nvim_buf_set_name(bufnr, "mynotes://" .. note.id)
      cache.upsert(note)
      vim.bo[bufnr].modified = false
      vim.notify("Note created", vim.log.levels.INFO)
    end)
  else
    local id = vim.b[bufnr].mynotes_id
    api.update(id, title, content, function(err, note)
      if err then
        vim.notify("Failed to save note: " .. err, vim.log.levels.ERROR)
        return
      end
      cache.upsert(note)
      vim.bo[bufnr].modified = false
      vim.notify("Note saved", vim.log.levels.INFO)
    end)
  end
end

--- Close the buffer for a given note id (used after delete).
---@param id string
function M.close(id)
  local name = "mynotes://" .. id
  local bufnr = find_buf_by_name(name)
  if bufnr then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

return M
