local curl = require("plenary.curl")
local config = require("mybot-notes.config")

local M = {}

--- Build common headers for API requests.
---@param with_content_type boolean
---@return table
local function headers(with_content_type)
  local h = {
    Authorization = "Bearer " .. config.get_api_key(),
    Accept = "application/json",
  }
  if with_content_type then
    h["Content-Type"] = "application/json"
  end
  return h
end

--- Handle plenary.curl response and call user callback.
---@param response table plenary.curl response
---@param callback function(err: string|nil, data: table|nil)
local function handle_response(response, callback)
  vim.schedule(function()
    if response.exit ~= 0 then
      callback("Request failed", nil)
      return
    end
    if response.status < 200 or response.status >= 300 then
      callback("HTTP " .. response.status .. ": " .. (response.body or ""), nil)
      return
    end
    local ok, decoded = pcall(vim.json.decode, response.body)
    if not ok then
      callback("Failed to decode response", nil)
      return
    end
    callback(nil, decoded)
  end)
end

--- GET /notes — fetch all notes
---@param callback fun(err: string|nil, notes: mybot.Note[]|nil)
function M.get_all(callback)
  curl.get({
    url = config.values.base_url .. "/notes",
    headers = headers(false),
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- GET /notes?q=<query> — search notes
---@param query string
---@param callback fun(err: string|nil, notes: mybot.Note[]|nil)
function M.search(query, callback)
  curl.get({
    url = config.values.base_url .. "/notes",
    headers = headers(false),
    query = { q = query },
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- GET /notes/{id} — get single note
---@param id string
---@param callback fun(err: string|nil, note: mybot.Note|nil)
function M.get(id, callback)
  curl.get({
    url = config.values.base_url .. "/notes/" .. id,
    headers = headers(false),
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- POST /notes — create note
---@param title string
---@param content string
---@param callback fun(err: string|nil, note: mybot.Note|nil)
function M.create(title, content, callback)
  curl.post({
    url = config.values.base_url .. "/notes",
    headers = headers(true),
    body = vim.json.encode({ title = title, content = content }),
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- PUT /notes/{id} — update note
---@param id string
---@param title string
---@param content string
---@param callback fun(err: string|nil, note: mybot.Note|nil)
function M.update(id, title, content, callback)
  curl.put({
    url = config.values.base_url .. "/notes/" .. id,
    headers = headers(true),
    body = vim.json.encode({ title = title, content = content }),
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- DELETE /notes/{id} — soft delete
---@param id string
---@param callback fun(err: string|nil, data: table|nil)
function M.delete(id, callback)
  curl.delete({
    url = config.values.base_url .. "/notes/" .. id,
    headers = headers(false),
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- GET /notes/daily — get or create today's daily note
---@param callback fun(err: string|nil, note: mybot.Note|nil)
function M.daily(callback)
  curl.get({
    url = config.values.base_url .. "/notes/daily",
    headers = headers(false),
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- GET /notes/templates — fetch all templates
---@param callback fun(err: string|nil, templates: mybot.Template[]|nil)
function M.get_templates(callback)
  curl.get({
    url = config.values.base_url .. "/notes/templates",
    headers = headers(false),
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- GET /notes/new?template={id} — get resolved template content
---@param id string
---@param callback fun(err: string|nil, resolved: mybot.Template|nil)
function M.resolve_template(id, callback)
  curl.get({
    url = config.values.base_url .. "/notes/new",
    headers = headers(false),
    query = { template = id },
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- PUT /notes/{id} with is_template=true — convert note to template
---@param id string
---@param title string
---@param content string
---@param callback fun(err: string|nil, note: mybot.Note|nil)
function M.make_template(id, title, content, callback)
  curl.put({
    url = config.values.base_url .. "/notes/" .. id,
    headers = headers(true),
    body = vim.json.encode({ title = title, content = content }),
    query = { is_template = "true" },
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- PUT /notes/templates/{id} — update template
---@param id string
---@param title string
---@param content string
---@param callback fun(err: string|nil, template: mybot.Template|nil)
function M.update_template(id, title, content, callback)
  curl.put({
    url = config.values.base_url .. "/notes/templates/" .. id,
    headers = headers(true),
    body = vim.json.encode({ title = title, content = content }),
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- DELETE /notes/templates/{id} — soft delete template
---@param id string
---@param callback fun(err: string|nil, data: table|nil)
function M.delete_template(id, callback)
  curl.delete({
    url = config.values.base_url .. "/notes/templates/" .. id,
    headers = headers(false),
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- GET /today?date=YYYY-MM-DD — fetch today dashboard data
---@param date string|nil
---@param callback fun(err: string|nil, data: mybot.TodayData|nil)
function M.today(date, callback)
  local query = nil
  if date and date ~= "" then
    query = { date = date }
  end
  curl.get({
    url = config.values.base_url .. "/today",
    headers = headers(false),
    query = query,
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- POST /tasks/{id}/complete — mark task done
---@param id string
---@param callback fun(err: string|nil, data: table|nil)
function M.complete_task(id, callback)
  curl.post({
    url = config.values.base_url .. "/tasks/" .. id .. "/complete",
    headers = headers(false),
    body = "",
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- POST /tasks/{id}/uncomplete — mark task undone
---@param id string
---@param callback fun(err: string|nil, data: table|nil)
function M.uncomplete_task(id, callback)
  curl.post({
    url = config.values.base_url .. "/tasks/" .. id .. "/uncomplete",
    headers = headers(false),
    body = "",
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- PUT /tasks/{id} — update task (full replacement)
---@param id string
---@param body table
---@param callback fun(err: string|nil, data: table|nil)
function M.update_task(id, body, callback)
  curl.put({
    url = config.values.base_url .. "/tasks/" .. id,
    headers = headers(true),
    body = vim.json.encode(body),
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

--- POST /today/meetings/{eventId}/note — create or get meeting note
---@param event_id string
---@param body table
---@param callback fun(err: string|nil, note: mybot.Note|nil)
function M.create_meeting_note(event_id, body, callback)
  curl.post({
    url = config.values.base_url .. "/today/meetings/" .. event_id .. "/note",
    headers = headers(true),
    body = vim.json.encode(body),
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

return M
