local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

--- Only activate in note buffers to avoid firing on [ in every file.
---@return boolean
function source:is_available()
  return vim.b.mynotes_id ~= nil or vim.b.mynotes_is_new == true
end

---@return string[]
function source:get_trigger_characters()
  return { "[" }
end

---@param params table
---@param callback function
function source:complete(params, callback)
  local line = params.context.cursor_before_line
  -- Check if cursor is after [[ pattern
  local trigger = line:match("%[%[([^%]]*)$")
  if not trigger then
    callback({ items = {}, isIncomplete = false })
    return
  end

  local titles = require("mybot-notes.cache").get_titles()
  local items = {}
  for _, t in ipairs(titles) do
    items[#items + 1] = {
      label = t.title,
      insertText = t.title .. "]]",
      filterText = "[[" .. t.title,
      kind = 18, -- Reference
    }
  end
  callback({ items = items, isIncomplete = false })
end

---@return string
function source:get_keyword_pattern()
  return "\\%(\\[\\[\\)\\zs[^\\]]*"
end

return source
