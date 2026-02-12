# mybot-notes.nvim

Neovim plugin that talks to my personal notes API so I never have to leave the editor to jot something down.

**Fair warning:** this is built for [mybot](https://github.com/efueyo)'s specific notes API. Unless you happen to be running a compatible backend, this plugin won't do much for you. That said, feel free to poke around if you're building something similar.

## What it does

- Notes live in buffers. `:w` saves to the server. That's the whole mental model.
- `[[wikilinks]]` and `#tags` are navigable with `gf` -- links open notes, tags open a Telescope picker.
- Telescope pickers for searching notes and browsing tags.
- nvim-cmp source for `[[wikilink]]` autocompletion (type `[[` and get note titles).
- Local cache so search and completion feel instant instead of waiting on HTTP round-trips.
- Daily notes command for the "what did I do today" ritual.

## Dependencies

- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) -- required (HTTP)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) -- optional (search/tags)
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) -- optional (wikilink completion)

## Setup

```lua
require("mybot-notes").setup({
  base_url = "https://your-instance.example.com",
  api_key = "mk_...",
  -- or fetch it from a password manager:
  -- api_key_cmd = { "pass", "show", "mybot/api-key" },
})
```

`base_url` and `api_key` fall back to the `MYBOT_NOTES_BASE_URL` and `MYBOT_NOTES_API_KEY` environment variables when not provided, so you can also just:

```lua
require("mybot-notes").setup({})
```

All config with defaults:

```lua
{
  base_url = "",              -- required
  api_key = "",               -- or use api_key_cmd
  api_key_cmd = nil,          -- e.g. { "pass", "show", "mybot/api-key" }
  cache_ttl = 900,            -- 15 min
  cache_dir = vim.fn.stdpath("data") .. "/mybot-notes",
  keymaps = {
    create = "<leader>nn",
    search = "<leader>ns",
    daily  = "<leader>nd",
    tags   = "<leader>nt",
  },
}
```

Set any keymap to `false` to disable it.

## Commands

| Command | What it does |
|---------|-------------|
| `:NotesNew` | New note buffer |
| `:NotesDaily` | Today's daily note |
| `:NotesSearch` | Telescope fuzzy search |
| `:NotesTags` | Telescope tag browser |
| `:NotesDelete` | Delete current note (asks first) |
| `:NotesSync` | Force-refresh the cache |

## Navigation

Inside note buffers, `gf` is overloaded:

- On `[[Some Title]]` -- jumps to that note (creates it if it doesn't exist)
- On `#sometag` -- opens Telescope filtered by that tag
- Anywhere else -- normal `gf` behavior
