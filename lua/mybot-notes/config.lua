local M = {}

M.defaults = {
  base_url = "",
  api_key = "",
  api_key_cmd = nil,
  cache_ttl = 900,
  cache_dir = vim.fn.stdpath("data") .. "/mybot-notes",
  keymaps = {
    create = "<leader>nn",
    search = "<leader>ns",
    daily = "<leader>nd",
    tags = "<leader>nt",
    today = "<leader>nr",
  },
}

M.values = {}

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

  if M.values.base_url == "" then
    M.values.base_url = vim.env.MYBOT_NOTES_BASE_URL or ""
  end

  if M.values.api_key == "" or M.values.api_key == nil then
    M.values.api_key = vim.env.MYBOT_NOTES_API_KEY or ""
  end

  if M.values.base_url == "" then
    vim.notify("mybot-notes: base_url is required", vim.log.levels.ERROR)
    return
  end

  if (M.values.api_key == "" or M.values.api_key == nil) and M.values.api_key_cmd == nil then
    vim.notify("mybot-notes: api_key or api_key_cmd is required", vim.log.levels.ERROR)
    return
  end

  -- Resolve api_key_cmd if provided (takes priority over api_key)
  if M.values.api_key_cmd then
    local result = vim.system(M.values.api_key_cmd, { text = true }):wait()
    if result.code ~= 0 then
      vim.notify("mybot-notes: api_key_cmd failed: " .. (result.stderr or ""), vim.log.levels.ERROR)
      return
    end
    M.values._resolved_api_key = vim.trim(result.stdout)
  end
end

function M.get_api_key()
  if M.values._resolved_api_key then
    return M.values._resolved_api_key
  end
  return M.values.api_key
end

return M
