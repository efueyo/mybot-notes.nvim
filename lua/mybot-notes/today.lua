local api = require("mybot-notes.api")

local M = {}

-- Namespace for extmark highlights
local ns = vim.api.nvim_create_namespace("mybot_today")

local BAR_WIDTH = 28

local spinner_frames = { "\u{280b}", "\u{2819}", "\u{2839}", "\u{2838}", "\u{283c}", "\u{2834}", "\u{2826}", "\u{2827}", "\u{2807}", "\u{280f}" }
local loading_timer = {} -- keyed by bufnr

--- Define highlight groups with default = true so users can override.
local function setup_highlights()
  vim.api.nvim_set_hl(0, "MybotCapacityCompleted", { default = true, link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "MybotCapacityPlanned", { default = true, link = "Function" })
  vim.api.nvim_set_hl(0, "MybotCapacityMeetings", { default = true, link = "WarningMsg" })
  vim.api.nvim_set_hl(0, "MybotTodayLegend", { default = true, link = "Comment" })
end

--- Format minutes into a human-readable string (e.g. 90 -> "1h30m").
---@param minutes number
---@return string
local function format_duration(minutes)
  if not minutes or minutes <= 0 then
    return "0m"
  end
  local h = math.floor(minutes / 60)
  local m = minutes % 60
  if h > 0 and m > 0 then
    return h .. "h" .. m .. "m"
  elseif h > 0 then
    return h .. "h"
  else
    return m .. "m"
  end
end

--- Parse a time estimate string into minutes.
--- Handles: "30m" -> 30, "1h" -> 60, "1h30m" -> 90, "30" -> 30, "" -> 0.
---@param input string
---@return number|nil minutes, or nil if invalid
local function parse_estimate(input)
  if not input or vim.trim(input) == "" then
    return 0
  end
  input = vim.trim(input):lower()
  local h, m = input:match("^(%d+)h(%d+)m$")
  if h and m then
    return tonumber(h) * 60 + tonumber(m)
  end
  h = input:match("^(%d+)h$")
  if h then
    return tonumber(h) * 60
  end
  m = input:match("^(%d+)m$")
  if m then
    return tonumber(m)
  end
  local plain = input:match("^(%d+)$")
  if plain then
    return tonumber(plain)
  end
  return nil
end

--- Format a date string like "2026-02-14" into "Sat Feb 14".
---@param date_str string YYYY-MM-DD
---@return string
local function format_date_heading(date_str)
  local y, mo, d = date_str:match("^(%d+)-(%d+)-(%d+)$")
  if not y then
    return date_str
  end
  local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d) })
  return os.date("%a %b %d", t)
end

--- Format a time range for an event.
---@param event mybot.Event
---@return string
local function format_event_time(event)
  if event.is_all_day then
    return "All day"
  end
  local function fmt(iso)
    if not iso then
      return "?"
    end
    local h, m = iso:match("T(%d%d):(%d%d)")
    if h and m then
      return h .. ":" .. m
    end
    return ""
  end
  return fmt(event.start_time) .. " - " .. fmt(event.end_time)
end

--- Build a single event line.
---@param event mybot.Event
---@return string
local function format_event_line(event)
  local line = format_event_time(event) .. " " .. event.title
  if event.calendar_name and event.calendar_name ~= "" then
    line = line .. " (" .. event.calendar_name .. ")"
  end
  if event.has_note then
    line = line .. " \u{1f4dd}"
  end
  return line
end

--- Build a single task line.
---@param task mybot.Task
---@return string
local function format_task_line(task)
  local marker = task.completed and "\u{25cf}" or "\u{25cb}"
  local parts = { marker, " ", task.title }
  if task.estimated_minutes and task.estimated_minutes > 0 then
    parts[#parts + 1] = " [" .. format_duration(task.estimated_minutes) .. "]"
  end
  if task.tags and type(task.tags) == "table" then
    for _, tag in ipairs(task.tags) do
      parts[#parts + 1] = " #" .. tag
    end
  end
  return table.concat(parts)
end

--- Compute the number of bar blocks for each segment.
---@param completed number
---@param planned number
---@param meetings number
---@param total number
---@return number c_blocks, number p_blocks, number m_blocks
local function compute_bar_blocks(completed, planned, meetings, total)
  local c_blocks, p_blocks, m_blocks = 0, 0, 0
  if total > 0 then
    c_blocks = math.floor((completed / total) * BAR_WIDTH + 0.5)
    p_blocks = math.floor((planned / total) * BAR_WIDTH + 0.5)
    m_blocks = math.floor((meetings / total) * BAR_WIDTH + 0.5)
    local sum = c_blocks + p_blocks + m_blocks
    while sum > BAR_WIDTH do
      if m_blocks > 0 then
        m_blocks = m_blocks - 1
      elseif p_blocks > 0 then
        p_blocks = p_blocks - 1
      elseif c_blocks > 0 then
        c_blocks = c_blocks - 1
      end
      sum = sum - 1
    end
  end
  return c_blocks, p_blocks, m_blocks
end

--- Build the capacity bar string.
---@param data mybot.TodayData
---@return string bar_line, string legend_line, number c_blocks, number p_blocks, number m_blocks
local function build_capacity_bar(data)
  local total = data.total_minutes or 0
  local completed = data.completed_minutes or 0
  local planned = data.planned_minutes or 0
  local meetings = data.meeting_minutes or 0

  local used = completed + planned + meetings
  local used_str = format_duration(used)
  local total_str = format_duration(total)

  local c_blocks, p_blocks, m_blocks = compute_bar_blocks(completed, planned, meetings, total)
  local empty = math.max(0, BAR_WIDTH - c_blocks - p_blocks - m_blocks)

  local bar = "["
    .. string.rep("\u{2588}", c_blocks)
    .. string.rep("\u{2588}", p_blocks)
    .. string.rep("\u{2588}", m_blocks)
    .. string.rep("\u{2591}", empty)
    .. "]"
    .. " "
    .. used_str
    .. " / "
    .. total_str

  local legend = "\u{25a0} Completed "
    .. format_duration(completed)
    .. "  \u{25a0} Planned "
    .. format_duration(planned)
    .. "  \u{25a0} Meetings "
    .. format_duration(meetings)

  return bar, legend, c_blocks, p_blocks, m_blocks
end

--- Build all buffer lines and the line map from API data.
---@param data mybot.TodayData
---@return string[], table<number, mybot.LineMapEntry>, mybot.HighlightRange[]
local function build_lines(data)
  local lines = {}
  local line_map = {}
  local highlights = {} -- { { line, col_start, col_end, hl_group } }

  -- Title
  lines[#lines + 1] = "# Today \u{2014} " .. format_date_heading(data.date)
  lines[#lines + 1] = ""

  -- Capacity section
  lines[#lines + 1] = "## Capacity"
  lines[#lines + 1] = ""
  local bar_line, legend_line, c_blocks, p_blocks, m_blocks = build_capacity_bar(data)
  local bar_ln = #lines + 1
  lines[#lines + 1] = bar_line

  -- Calculate highlight positions for the capacity bar segments
  -- "[" is 1 byte at col 0; each block char is 3 bytes (UTF-8)
  local offset = 1 -- after "["
  if c_blocks > 0 then
    highlights[#highlights + 1] = { bar_ln, offset, offset + c_blocks * 3, "MybotCapacityCompleted" }
  end
  offset = offset + c_blocks * 3
  if p_blocks > 0 then
    highlights[#highlights + 1] = { bar_ln, offset, offset + p_blocks * 3, "MybotCapacityPlanned" }
  end
  offset = offset + p_blocks * 3
  if m_blocks > 0 then
    highlights[#highlights + 1] = { bar_ln, offset, offset + m_blocks * 3, "MybotCapacityMeetings" }
  end

  local legend_ln = #lines + 1
  lines[#lines + 1] = legend_line
  highlights[#highlights + 1] = { legend_ln, 0, #legend_line, "MybotTodayLegend" }

  -- Events section
  local events = data.events or {}
  if #events > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Events"
    lines[#lines + 1] = ""
    for _, event in ipairs(events) do
      local ln = #lines + 1
      lines[#lines + 1] = format_event_line(event)
      line_map[ln] = { type = "event", event = event }
    end
  end

  -- Tasks section
  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Tasks"
  lines[#lines + 1] = ""
  local tasks = data.tasks or {}
  if #tasks == 0 then
    lines[#lines + 1] = "No tasks scheduled"
  else
    for _, task in ipairs(tasks) do
      local ln = #lines + 1
      lines[#lines + 1] = format_task_line(task)
      line_map[ln] = { type = "task", task = task }
    end
  end

  -- Legend
  lines[#lines + 1] = ""
  local legend_keys = "\u{23ce} action  e estimate  r refresh  ]d/[d day  q close"
  local legend_keys_ln = #lines + 1
  lines[#lines + 1] = legend_keys
  highlights[#highlights + 1] = { legend_keys_ln, 0, #legend_keys, "MybotTodayLegend" }
  line_map[legend_keys_ln] = { type = "legend" }

  return lines, line_map, highlights
end

--- Stop the loading spinner for a buffer.
---@param bufnr number
local function stop_loading_spinner(bufnr)
  local timer = loading_timer[bufnr]
  if timer then
    timer:stop()
    timer:close()
    loading_timer[bufnr] = nil
  end
end

--- Show a loading placeholder with animated spinner.
---@param bufnr number
---@param date string|nil
local function show_loading(bufnr, date)
  stop_loading_spinner(bufnr)

  local heading = "# Today"
  if date and date ~= "" then
    heading = heading .. " \u{2014} " .. format_date_heading(date)
  end

  local frame_idx = 1
  local function draw_frame()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      stop_loading_spinner(bufnr)
      return
    end
    local text = spinner_frames[frame_idx] .. " Loading..."
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, { text })
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].modified = false
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 2, 3)
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, 2, 0, {
      end_col = #text,
      hl_group = "MybotTodayLegend",
    })
    frame_idx = frame_idx % #spinner_frames + 1
  end

  -- Set initial content
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { heading, "", "" })
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
  draw_frame()

  local timer = vim.uv.new_timer()
  loading_timer[bufnr] = timer
  timer:start(80, 80, vim.schedule_wrap(function()
    draw_frame()
  end))
end

--- Render data into the buffer.
---@param bufnr number
---@param data mybot.TodayData
---@param restore_task_id string|nil task ID to restore cursor to
local function render(bufnr, data, restore_task_id)
  stop_loading_spinner(bufnr)
  -- line_map here is the freshly-built Lua table with integer keys (not from vim.b)
  local lines, line_map, highlights = build_lines(data)

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false

  -- Store line map and date nav as buffer-local vars
  vim.b[bufnr].mynotes_today_lines = line_map
  vim.b[bufnr].mynotes_today_date = data.date
  vim.b[bufnr].mynotes_today_prev = data.prev_date
  vim.b[bufnr].mynotes_today_next = data.next_date

  -- Update buffer name to reflect current date
  local new_name = "mynotes://today/" .. data.date
  pcall(vim.api.nvim_buf_set_name, bufnr, new_name)

  -- Apply extmark highlights
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    local ln, col_start, col_end, hl_group = hl[1], hl[2], hl[3], hl[4]
    -- extmark line is 0-indexed, build_lines uses 1-indexed
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, ln - 1, col_start, {
      end_col = col_end,
      hl_group = hl_group,
    })
  end

  -- Restore cursor position by task ID
  if restore_task_id then
    for ln, entry in pairs(line_map) do
      if entry.type == "task" and entry.task.id == restore_task_id then
        pcall(vim.api.nvim_win_set_cursor, 0, { ln, 0 })
        return
      end
    end
  end
end

--- Fetch data and render into the buffer.
---@param bufnr number
---@param date string|nil
---@param restore_task_id string|nil
local function fetch_and_render(bufnr, date, restore_task_id)
  vim.b[bufnr].mynotes_today_loading = true
  show_loading(bufnr, date)
  api.today(date, function(err, data)
    vim.b[bufnr].mynotes_today_loading = false
    if err then
      stop_loading_spinner(bufnr)
      vim.notify("Failed to fetch today data: " .. err, vim.log.levels.ERROR)
      return
    end
    render(bufnr, data, restore_task_id)
  end)
end

--- Set up buffer-local keymaps.
---@param bufnr number
local function setup_keymaps(bufnr)
  local opts = { buffer = bufnr, nowait = true, silent = true }

  -- <CR> action: toggle task completion / open or create event note
  vim.keymap.set("n", "<CR>", function()
    M.action(bufnr)
  end, vim.tbl_extend("force", opts, { desc = "Mybot Action on current line" }))

  -- e edit time estimate
  vim.keymap.set("n", "e", function()
    M.edit_estimate(bufnr)
  end, vim.tbl_extend("force", opts, { desc = "Mybot Edit time estimate" }))

  -- r refresh
  vim.keymap.set("n", "r", function()
    M.refresh(bufnr)
  end, vim.tbl_extend("force", opts, { desc = "Mybot Refresh today" }))

  -- ]d next day
  vim.keymap.set("n", "]d", function()
    if vim.b[bufnr].mynotes_today_loading then
      return
    end
    local next_date = vim.b[bufnr].mynotes_today_next
    if next_date and next_date ~= "" then
      fetch_and_render(bufnr, next_date)
    end
  end, vim.tbl_extend("force", opts, { desc = "Mybot Next day" }))

  -- [d previous day
  vim.keymap.set("n", "[d", function()
    if vim.b[bufnr].mynotes_today_loading then
      return
    end
    local prev_date = vim.b[bufnr].mynotes_today_prev
    if prev_date and prev_date ~= "" then
      fetch_and_render(bufnr, prev_date)
    end
  end, vim.tbl_extend("force", opts, { desc = "Mybot Previous day" }))

  -- q close
  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end, vim.tbl_extend("force", opts, { desc = "Mybot Close today buffer" }))
end

--- Get the current task entry under the cursor, if any.
---@param bufnr number
---@return mybot.LineMapEntry|nil
local function get_cursor_entry(bufnr)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local line_map = vim.b[bufnr].mynotes_today_lines
  if not line_map then
    return nil
  end
  -- vim.b[] converts integer keys to string keys when reading back
  return line_map[tostring(line)] or line_map[line]
end

--- Dispatch action based on the current line type.
---@param bufnr number
function M.action(bufnr)
  if vim.b[bufnr].mynotes_today_loading then
    return
  end
  local entry = get_cursor_entry(bufnr)
  if not entry then
    return
  end
  if entry.type == "task" then
    M.toggle_task(bufnr)
  elseif entry.type == "event" then
    M.event_note(bufnr)
  end
end

--- Toggle task completion on the current line.
---@param bufnr number
function M.toggle_task(bufnr)
  if vim.b[bufnr].mynotes_today_loading then
    return
  end
  local entry = get_cursor_entry(bufnr)
  if not entry or entry.type ~= "task" then
    return
  end
  local task = entry.task
  local task_id = task.id
  local date = vim.b[bufnr].mynotes_today_date

  vim.b[bufnr].mynotes_today_loading = true
  local fn = task.completed and api.uncomplete_task or api.complete_task
  fn(task_id, function(err)
    vim.b[bufnr].mynotes_today_loading = false
    if err then
      vim.notify("Failed to toggle task: " .. err, vim.log.levels.ERROR)
      return
    end
    fetch_and_render(bufnr, date, task_id)
  end)
end

--- Open or create a note for the event on the current line.
--- The backend handles both cases: returns existing note or creates a new one.
---@param bufnr number
function M.event_note(bufnr)
  if vim.b[bufnr].mynotes_today_loading then
    return
  end
  local entry = get_cursor_entry(bufnr)
  if not entry or entry.type ~= "event" then
    return
  end
  local event = entry.event
  local date = vim.b[bufnr].mynotes_today_date

  local body = {
    title = event.title,
    date = date or "",
    attendees = event.attendees,
  }
  if not event.is_all_day and event.start_time then
    local h, m = event.start_time:match("T(%d%d):(%d%d)")
    if h and m then
      local hour = tonumber(h)
      local suffix = hour >= 12 and "PM" or "AM"
      if hour > 12 then
        hour = hour - 12
      elseif hour == 0 then
        hour = 12
      end
      body.time = hour .. ":" .. m .. " " .. suffix
    end
  end

  vim.b[bufnr].mynotes_today_loading = true
  api.create_meeting_note(event.id, body, function(err, note)
    vim.b[bufnr].mynotes_today_loading = false
    if err then
      vim.notify("Failed to open meeting note: " .. err, vim.log.levels.ERROR)
      return
    end
    require("mybot-notes.cache").upsert(note)
    require("mybot-notes.buffer").open(note)
    fetch_and_render(bufnr, date)
  end)
end

--- Edit time estimate for the task on the current line.
---@param bufnr number
function M.edit_estimate(bufnr)
  if vim.b[bufnr].mynotes_today_loading then
    return
  end
  local entry = get_cursor_entry(bufnr)
  if not entry or entry.type ~= "task" then
    return
  end
  local task = entry.task
  local task_id = task.id
  local date = vim.b[bufnr].mynotes_today_date

  vim.b[bufnr].mynotes_today_loading = true
  vim.ui.input({ prompt = "Estimate (e.g. 30m, 1h, 1h30m): " }, function(input)
    if input == nil then
      vim.b[bufnr].mynotes_today_loading = false
      return
    end
    local minutes = parse_estimate(input)
    if minutes == nil then
      vim.b[bufnr].mynotes_today_loading = false
      vim.notify("Invalid estimate format. Use e.g. 30m, 1h, 1h30m", vim.log.levels.ERROR)
      return
    end
    local body = {
      title = task.title,
      tags = task.tags or {},
      scheduled_for = (task.scheduled_for or ""):match("^(%d%d%d%d%-%d%d%-%d%d)") or date,
      estimated_minutes = minutes,
    }
    api.update_task(task_id, body, function(err)
      vim.b[bufnr].mynotes_today_loading = false
      if err then
        vim.notify("Failed to update estimate: " .. err, vim.log.levels.ERROR)
        return
      end
      fetch_and_render(bufnr, date, task_id)
    end)
  end)
end

--- Refresh the current today buffer.
---@param bufnr number
function M.refresh(bufnr)
  if vim.b[bufnr].mynotes_today_loading then
    return
  end
  local date = vim.b[bufnr].mynotes_today_date
  local entry = get_cursor_entry(bufnr)
  local restore_id = nil
  if entry and entry.type == "task" then
    restore_id = entry.task.id
  end
  fetch_and_render(bufnr, date, restore_id)
end

--- Find an existing today buffer.
---@return number|nil bufnr
local function find_today_buf()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name == "mynotes://today" or name:match("^mynotes://today/") then
        return bufnr
      end
    end
  end
  return nil
end

--- Open the today dashboard buffer.
---@param date string|nil optional YYYY-MM-DD date
function M.open(date)
  setup_highlights()

  -- Check for existing today buffer
  local existing = find_today_buf()
  if existing then
    vim.api.nvim_set_current_buf(existing)
    fetch_and_render(existing, date)
    return
  end

  -- Create new unlisted scratch buffer for the dashboard
  local bufnr = vim.api.nvim_create_buf(false, true)
  local buf_name = "mynotes://today"
  if date and date ~= "" then
    buf_name = "mynotes://today/" .. date
  end
  vim.api.nvim_buf_set_name(bufnr, buf_name)

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].buflisted = true

  setup_keymaps(bufnr)

  vim.api.nvim_set_current_buf(bufnr)
  fetch_and_render(bufnr, date)
end

return M
