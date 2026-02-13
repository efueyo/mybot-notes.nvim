local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

--- Only activate in note buffers to avoid firing on [ and # in every file.
---@return boolean
function source:is_available()
  return vim.b.mynotes_id ~= nil or vim.b.mynotes_is_new == true
end

---@return string[]
function source:get_trigger_characters()
  return { "[", "#" }
end

---@param params table
---@param callback function
function source:complete(params, callback)
  local line = params.context.cursor_before_line
  local cache = require("mybot-notes.cache")

  -- [[wikilink]] completion
  local wikilink = line:match("%[%[([^%]]*)$")
  if wikilink then
    local titles = cache.get_titles()
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
    return
  end

  -- #tag completion
  local tag = line:match("#(%w*)$")
  if tag then
    local tags = cache.get_tags()
    local items = {}
    for _, t in ipairs(tags) do
      items[#items + 1] = {
        label = "#" .. t,
        insertText = t,
        filterText = "#" .. t,
        kind = 14, -- Keyword
      }
    end
    callback({ items = items, isIncomplete = false })
    return
  end

  callback({ items = {}, isIncomplete = false })
end

---@return string
function source:get_keyword_pattern()
  return "\\%(\\[\\[\\)\\zs[^\\]]*\\|#\\zs\\w*"
end

return source
