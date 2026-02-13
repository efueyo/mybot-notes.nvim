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

--- Add the mybot_notes cmp source to the buffer's completion sources.
local function setup_cmp()
  local ok, cmp = pcall(require, "cmp")
  if not ok then
    return
  end
  local sources = { { name = "mybot_notes" } }
  for _, s in ipairs(cmp.get_config().sources or {}) do
    if s.name ~= "mybot_notes" then
      sources[#sources + 1] = s
    end
  end
  cmp.setup.buffer({ sources = sources })
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

--- Build buffer content from separate title and content fields.
--- If content already starts with a heading matching the title, use content as-is.
--- Otherwise prepend "# {title}\n\n".
---@param title string
---@param content string
---@return string
local function build_buffer_content(title, content)
  content = content or ""
  local first_line = content:match("^([^\n]*)")
  if first_line then
    local heading = first_line:match("^#+ (.+)")
    if heading and vim.trim(heading) == title then
      return content
    end
  end
  if content == "" then
    return "# " .. title .. "\n\n"
  end
  return "# " .. title .. "\n\n" .. content
end

--- Strip the leading title heading from buffer lines for API submission.
--- Removes the first markdown heading that matches the title, plus trailing blank lines.
---@param lines string[]
---@param title string
---@return string content without the title heading
local function strip_title_heading(lines, title)
  local start = 1
  for i, line in ipairs(lines) do
    local heading = line:match("^#+ (.+)")
    if heading and vim.trim(heading) == title then
      start = i + 1
      break
    elseif vim.trim(line) ~= "" then
      -- Non-heading, non-empty line first — nothing to strip
      return table.concat(lines, "\n")
    end
  end
  -- Skip blank lines immediately after the heading
  while start <= #lines and vim.trim(lines[start]) == "" do
    start = start + 1
  end
  local content_lines = {}
  for i = start, #lines do
    content_lines[#content_lines + 1] = lines[i]
  end
  return table.concat(content_lines, "\n")
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

  -- Populate content: title heading + body
  local buf_content = build_buffer_content(note.title or "", note.content or "")
  local lines = vim.split(buf_content, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Set metadata
  vim.b[bufnr].mynotes_id = note.id
  vim.b[bufnr].mynotes_title = note.title
  vim.b[bufnr].mynotes_is_new = false

  -- Set buffer options and autocmd
  set_buf_options(bufnr)
  register_write_autocmd(bufnr)
  require("mybot-notes.navigation").setup_buffer_keymaps(bufnr)

  -- Switch to the buffer
  vim.api.nvim_set_current_buf(bufnr)
  setup_cmp()
end

--- Create a new empty note buffer.
--- If title and content are provided, builds buffer as "# title\n\ncontent".
--- If only title is provided, pre-populates with "# title\n\n".
---@param title string|nil
---@param content string|nil
function M.create_new(title, content)
  local name = "mynotes://new-" .. os.time()
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, name)

  -- Pre-populate buffer
  if title and title ~= "" then
    local buf_content = build_buffer_content(title, content or "")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(buf_content, "\n", { plain = true }))
  elseif content and content ~= "" then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n", { plain = true }))
  end

  -- Set metadata
  vim.b[bufnr].mynotes_is_new = true

  -- Set buffer options and autocmd
  set_buf_options(bufnr)
  register_write_autocmd(bufnr)
  require("mybot-notes.navigation").setup_buffer_keymaps(bufnr)

  -- Switch to the buffer
  vim.api.nvim_set_current_buf(bufnr)
  setup_cmp()
end

--- Open an existing template in a buffer for editing.
--- Saves go to PUT /notes/templates/{id} via the mynotes_is_template flag.
---@param template table
function M.open_template(template)
  local name = "mynotes://template/" .. template.id

  local existing = find_buf_by_name(name)
  if existing then
    vim.api.nvim_set_current_buf(existing)
    return
  end

  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, name)

  local buf_content = build_buffer_content(template.title or "", template.content or "")
  local lines = vim.split(buf_content, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  vim.b[bufnr].mynotes_id = template.id
  vim.b[bufnr].mynotes_title = template.title
  vim.b[bufnr].mynotes_is_new = false
  vim.b[bufnr].mynotes_is_template = true

  set_buf_options(bufnr)
  register_write_autocmd(bufnr)
  require("mybot-notes.navigation").setup_buffer_keymaps(bufnr)

  vim.api.nvim_set_current_buf(bufnr)
  setup_cmp()
end

--- BufWriteCmd handler — called on :w in a note buffer.
---@param bufnr number
function M.save(bufnr)
  local api = require("mybot-notes.api")
  local cache = require("mybot-notes.cache")

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local title = M.extract_title(bufnr)
  local content = strip_title_heading(lines, title)

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
  elseif vim.b[bufnr].mynotes_is_template then
    local id = vim.b[bufnr].mynotes_id
    api.update_template(id, title, content, function(err, template)
      if err then
        vim.notify("Failed to save template: " .. err, vim.log.levels.ERROR)
        return
      end
      cache.upsert_template(template)
      vim.bo[bufnr].modified = false
      vim.notify("Template saved", vim.log.levels.INFO)
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
