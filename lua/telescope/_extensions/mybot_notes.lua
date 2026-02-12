local telescope = require("mybot-notes.telescope")

return require("telescope").register_extension({
  exports = {
    mybot_notes = telescope.search,
    search = telescope.search,
    tags = telescope.tags,
  },
})
