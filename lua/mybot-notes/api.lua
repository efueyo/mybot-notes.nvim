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
function M.daily(callback)
  curl.get({
    url = config.values.base_url .. "/notes/daily",
    headers = headers(false),
    callback = function(response)
      handle_response(response, callback)
    end,
  })
end

return M
