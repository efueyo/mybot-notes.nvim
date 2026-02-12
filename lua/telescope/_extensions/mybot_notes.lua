return require("telescope").register_extension({
  exports = {
    search = require("mybot-notes.telescope").search,
    tags = require("mybot-notes.telescope").tags,
  },
})
