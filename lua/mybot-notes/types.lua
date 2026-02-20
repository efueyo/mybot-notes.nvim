-- LuaLS type definitions for mybot-notes.nvim
-- This file contains no runtime code — it exists purely for LuaLS.

---@class mybot.Note
---@field id string
---@field title string
---@field content string
---@field tags? string[]
---@field current_version? number
---@field daily_date? string
---@field created_at? string
---@field updated_at? string

---@class mybot.Template
---@field id string
---@field title string
---@field content string

---@class mybot.Task
---@field id string
---@field title string
---@field completed boolean
---@field estimated_minutes? number
---@field tags? string[]
---@field scheduled_for? string

---@class mybot.Event
---@field id string
---@field title string
---@field is_all_day boolean
---@field start_time? string
---@field end_time? string
---@field calendar_name? string
---@field has_note boolean
---@field attendees? string[]

---@class mybot.TodayData
---@field date string
---@field prev_date string
---@field next_date string
---@field total_minutes number
---@field completed_minutes number
---@field planned_minutes number
---@field meeting_minutes number
---@field events mybot.Event[]
---@field tasks mybot.Task[]

---@class mybot.LineMapTaskEntry
---@field type "task"
---@field task mybot.Task

---@class mybot.LineMapEventEntry
---@field type "event"
---@field event mybot.Event

---@class mybot.LineMapLegendEntry
---@field type "legend"

---@alias mybot.LineMapEntry mybot.LineMapTaskEntry|mybot.LineMapEventEntry|mybot.LineMapLegendEntry

---@class mybot.Keymaps
---@field create string|false
---@field search string|false
---@field daily string|false
---@field tags string|false
---@field today string|false

---@class mybot.Config
---@field base_url string
---@field api_key string
---@field api_key_cmd? string[]
---@field cache_ttl number
---@field cache_dir string
---@field keymaps mybot.Keymaps

---@class mybot.CacheState
---@field notes mybot.Note[]
---@field notes_by_id table<string, mybot.Note>
---@field notes_by_title table<string, mybot.Note>
---@field tags string[]
---@field last_synced_at number
---@field loaded boolean
---@field syncing boolean
---@field templates mybot.Template[]
---@field templates_last_synced_at number
---@field templates_syncing boolean

---@class mybot.HighlightRange
---@field [1] number line number (1-indexed)
---@field [2] number col_start (byte offset)
---@field [3] number col_end (byte offset)
---@field [4] string hl_group name

---@class mybot.NoteTitle
---@field id string
---@field title string

---@alias mybot.ApiCallback fun(err: string|nil, data: any)

return {}
