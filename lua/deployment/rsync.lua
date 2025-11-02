-- Rsync functionality for deployment.nvim
local M = {}

local Job = require("plenary.job")
local Path = require("plenary.path")

-- Build rsync command for full deployment
function M.build_rsync_command(config, server, project_root)
    local deployment_config = require("deployment.config")
    local cmd = { "rsync" }

    -- Add default options
    vim.list_extend(cmd, deployment_config.get().rsync_options)

    -- Conditionally add --delete flag
    if deployment_config.get().delete_remote_files then
        table.insert(cmd, "--delete")
    end

    -- Add custom options from config
    vim.list_extend(cmd, config.options)

    -- Add excludes
    for _, exclude in ipairs(config.exclude) do
        table.insert(cmd, "--exclude=" .. exclude)
    end

    -- Add includes (rsync processes includes before excludes)
    for _, include in ipairs(config.include) do
        table.insert(cmd, "--include=" .. include)
    end

    -- Source path
    local source_path = Path:new(project_root, server.local_path):absolute()
    if not source_path:match("/$") then
        source_path = source_path .. "/"
    end
    table.insert(cmd, source_path)

    -- Destination
    local dest = server.host .. ":" .. server.remote_path
    if not server.remote_path:match("/$") then
        dest = dest .. "/"
    end
    table.insert(cmd, dest)

    return cmd
end

-- Build rsync command for single file deployment
function M.build_file_rsync_command(config, server, project_root, relative_path)
    local cmd = { "rsync" }

    -- Add basic options for single file (no --delete for safety)
    local file_options = {
        "-avz",
        "--exclude=.git/",
        "--exclude=.DS_Store",
    }
    vim.list_extend(cmd, file_options)

    -- Add custom options from config
    vim.list_extend(cmd, config.options)

    -- Source file (full path)
    local source_file = Path:new(project_root, relative_path):absolute()
    table.insert(cmd, source_file)

    -- Destination (preserve directory structure)
    local dest = server.host .. ":" .. server.remote_path .. "/" .. relative_path
    table.insert(cmd, dest)

    return cmd
end

-- Execute rsync command
function M.execute_rsync(cmd, callback)
    local start_time = vim.loop.hrtime()

    Job:new({
        command = cmd[1],
        args = vim.list_slice(cmd, 2),
        on_exit = function(j, return_val)
            local end_time = vim.loop.hrtime()
            local duration = math.floor((end_time - start_time) / 1000000) -- Convert to milliseconds

            if return_val == 0 then
                callback(true, nil, duration)
            else
                local stderr = table.concat(j:stderr_result(), "\n")
                callback(false, stderr, duration)
            end
        end,
        on_stderr = function(_, _data)
            -- Store stderr for error reporting
        end,
    }):start()
end

-- Deploy to single server (full deployment)
function M.deploy_to_server(config, server, project_root, callback)
    local cmd = M.build_rsync_command(config, server, project_root)

    M.execute_rsync(cmd, function(success, error_msg, duration)
        callback(server, success, error_msg, duration)
    end)
end

-- Deploy single file to server
function M.deploy_single_file_to_server(config, server, project_root, relative_path, callback)
    local cmd = M.build_file_rsync_command(config, server, project_root, relative_path)

    M.execute_rsync(cmd, function(success, error_msg, duration)
        callback(server, success, error_msg, duration)
    end)
end

return M

