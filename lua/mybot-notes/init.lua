local M = {}

function M.setup(opts)
  local config = require("mybot-notes.config")
  config.setup(opts)
end

return M
