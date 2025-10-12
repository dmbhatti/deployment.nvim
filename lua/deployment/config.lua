-- Configuration module for deployment.nvim
local M = {}

-- Default configuration
M.defaults = {
  deployment_file = ".deployment",
  rsync_options = {
    "-avz",
    "--exclude=.git/",
    "--exclude=.DS_Store",
    "--exclude=node_modules/",
  },
  parallel_jobs = 5,
  timeout = 30000, -- 30 seconds
  debug = false,
  delete_remote_files = false,
}

-- Current configuration (will be merged with user options)
M.config = {}

-- Setup function to merge user config with defaults
function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", M.defaults, user_config or {})
end

-- Get current config
function M.get()
  return M.config
end

-- Update a specific config value
function M.set(key, value)
  M.config[key] = value
end

return M