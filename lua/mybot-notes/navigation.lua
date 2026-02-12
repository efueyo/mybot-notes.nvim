local M = {}

--- Find a [[wikilink]] title at the given column position in a line.
---@param line string
---@param col number 1-indexed cursor column
---@return string|nil title inside [[ ]] or nil
local function find_wikilink_at(line, col)
  local search_start = 1
  while true do
    local open_start, open_end = line:find("%[%[", search_start)
    if not open_start then
      break
    end
    local close_start, close_end = line:find("%]%]", open_end + 1)
    if not close_start then
      break
    end
    -- Check if cursor is inside this wikilink (from [[ to ]])
    if col >= open_start and col <= close_end then
      return line:sub(open_end + 1, close_start - 1)
    end
    search_start = close_end + 1
  end
  return nil
end

--- Find a #tag at the given column position in a line.
---@param line string
---@param col number 1-indexed cursor column
---@return string|nil tag name (without #) or nil
local function find_tag_at(line, col)
  for start_pos, tag, end_pos in line:gmatch("()#(%w+)()") do
    -- start_pos points to the #, end_pos points past the last char
    if col >= start_pos and col < end_pos then
      return tag
    end
  end
  return nil
end

--- Navigate to a note by title. If not found in cache, create a new note.
---@param title string
local function navigate_to_note(title)
  local cache = require("mybot-notes.cache")
  local buffer = require("mybot-notes.buffer")

  local note = cache.find_by_title(title)
  if note then
    buffer.open(note)
  else
    buffer.create_new(title)
  end
end

--- Handle gf keypress in a note buffer.
--- Checks for [[wikilink]] or #tag under cursor and navigates accordingly.
function M.handle_gf()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1 -- convert to 1-indexed

  -- Check for [[wikilink]] under cursor
  local wikilink_title = find_wikilink_at(line, col)
  if wikilink_title then
    navigate_to_note(wikilink_title)
    return
  end

  -- Check for #tag under cursor
  local tag = find_tag_at(line, col)
  if tag then
    require("mybot-notes.telescope").search({ default_tag = tag })
    return
  end

  -- Fallback to default gf
  vim.cmd("normal! gf")
end

--- Set up buffer-local navigation keymaps for a note buffer.
---@param bufnr number
function M.setup_buffer_keymaps(bufnr)
  vim.keymap.set("n", "gf", M.handle_gf, {
    buffer = bufnr,
    desc = "Navigate to [[wikilink]] or #tag under cursor",
  })
end

return M
