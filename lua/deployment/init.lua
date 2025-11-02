-- Main entry point for deployment.nvim
local M = {}

local Path = require("plenary.path")

-- Get project root directory
function M.get_project_root()
    local current_file = vim.api.nvim_buf_get_name(0)
    local current_dir = vim.fn.fnamemodify(current_file, ":h")

    -- Look for .deployment file up the directory tree
    local path = Path:new(current_dir)
    while path.filename ~= "/" do
        local deployment_file = Path:new(path.filename, require("deployment.config").get().deployment_file)
        if deployment_file:exists() then
            return path.filename
        end
        path = path:parent()
    end

    -- Fallback to git root if available
    local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
    if git_root and git_root ~= "" then
        return git_root
    end

    return vim.fn.getcwd()
end

-- Get current deployment configuration (supports both single and multi-config)
function M.get_current_config(project_root)
    local parser = require("deployment.parser")
    local deployment_file_path = project_root .. "/" .. require("deployment.config").get().deployment_file

    -- First try to parse as multi-config
    local multi_config, multi_err = parser.parse_multi_config_deployment(deployment_file_path)
    if multi_config and multi_config.configurations then
        if not multi_config.active then
            return nil, "No active configuration specified. Use :DeploySetActive <config_name>"
        end

        local active_config = multi_config.configurations[multi_config.active]
        if not active_config then
            return nil, "Active configuration '" .. multi_config.active .. "' not found"
        end

        return active_config, nil, multi_config.active, multi_config.configurations
    end

    -- Fallback to single config format
    local single_config, single_err = parser.parse_deployment_config(deployment_file_path)
    if single_config then
        return single_config, nil, "default", { default = single_config }
    end

    return nil, single_err or multi_err
end

-- Deploy to all servers in parallel
function M.deploy_all(show_progress)
    local project_root = M.get_project_root()
    local config, err = M.get_current_config(project_root)

    if not config then
        vim.notify("Deployment failed: " .. err, vim.log.levels.ERROR)
        return
    end

    if #config.servers == 0 then
        vim.notify("No servers configured in .deployment file", vim.log.levels.WARN)
        return
    end

    local results = {}
    local completed = 0
    local total = #config.servers

    if show_progress then
        vim.notify(string.format("Starting deployment to %d server(s)...", total), vim.log.levels.INFO)
    end

    local rsync = require("deployment.rsync")
    for _, server in ipairs(config.servers) do
        rsync.deploy_to_server(config, server, project_root, function(srv, success, error_msg, duration)
            completed = completed + 1

            table.insert(results, {
                server = srv,
                success = success,
                error = error_msg,
                duration = duration,
            })

            if show_progress then
                if success then
                    vim.notify(
                        string.format("✓ %s (%dms) [%d/%d]", srv.name, duration, completed, total),
                        vim.log.levels.INFO
                    )
                else
                    vim.notify(
                        string.format(
                            "✗ %s failed: %s [%d/%d]",
                            srv.name,
                            error_msg or "Unknown error",
                            completed,
                            total
                        ),
                        vim.log.levels.ERROR
                    )
                end
            end

            -- All deployments completed
            if completed == total then
                M.show_deployment_summary(results, show_progress)
            end
        end)
    end
end

-- Deploy to specific server
function M.deploy_to_specific_server(server_name)
    local project_root = M.get_project_root()
    local config, err = M.get_current_config(project_root)

    if not config then
        vim.notify("Deployment failed: " .. err, vim.log.levels.ERROR)
        return
    end

    local server = nil
    for _, srv in ipairs(config.servers) do
        if srv.name == server_name then
            server = srv
            break
        end
    end

    if not server then
        vim.notify("Server '" .. server_name .. "' not found in .deployment file", vim.log.levels.ERROR)
        return
    end

    vim.notify("Deploying to " .. server_name .. "...", vim.log.levels.INFO)

    local rsync = require("deployment.rsync")
    rsync.deploy_to_server(config, server, project_root, function(srv, success, error_msg, duration)
        if success then
            vim.notify(string.format("✓ %s deployed successfully (%dms)", srv.name, duration), vim.log.levels.INFO)
        else
            vim.notify(
                string.format("✗ %s deployment failed: %s", srv.name, error_msg or "Unknown error"),
                vim.log.levels.ERROR
            )
        end
    end)
end

-- Deploy current file to all servers
function M.deploy_current_file_to_all(show_progress)
    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file == "" then
        vim.notify("No file is currently open", vim.log.levels.WARN)
        return
    end

    local project_root = M.get_project_root()
    local config, err = M.get_current_config(project_root)

    if not config then
        vim.notify("Deployment failed: " .. err, vim.log.levels.ERROR)
        return
    end

    if #config.servers == 0 then
        vim.notify("No servers configured in .deployment file", vim.log.levels.WARN)
        return
    end

    -- Get relative path from project root to current file
    local relative_path = vim.fn.fnamemodify(current_file, ":.")
    local filename = vim.fn.fnamemodify(current_file, ":t")

    local results = {}
    local completed = 0
    local total = #config.servers

    if show_progress then
        vim.notify(string.format("Starting deployment of %s to %d server(s)...", filename, total), vim.log.levels.INFO)
    end

    local rsync = require("deployment.rsync")
    for _, server in ipairs(config.servers) do
        rsync.deploy_single_file_to_server(
            config,
            server,
            project_root,
            relative_path,
            function(srv, success, error_msg, duration)
                completed = completed + 1

                table.insert(results, {
                    server = srv,
                    success = success,
                    error = error_msg,
                    duration = duration,
                    filename = filename,
                })

                if show_progress then
                    if success then
                        vim.notify(
                            string.format(
                                "✓ %s deployed %s (%dms) [%d/%d]",
                                srv.name,
                                filename,
                                duration,
                                completed,
                                total
                            ),
                            vim.log.levels.INFO
                        )
                    else
                        vim.notify(
                            string.format(
                                "✗ %s failed to deploy %s: %s [%d/%d]",
                                srv.name,
                                filename,
                                error_msg or "Unknown error",
                                completed,
                                total
                            ),
                            vim.log.levels.ERROR
                        )
                    end
                end

                -- All deployments completed
                if completed == total then
                    M.show_file_deployment_summary(results, filename, show_progress)
                end
            end
        )
    end
end

-- Deploy current file to specific server
function M.deploy_current_file_to_server(server_name)
    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file == "" then
        vim.notify("No file is currently open", vim.log.levels.WARN)
        return
    end

    local project_root = M.get_project_root()
    local config, err = M.get_current_config(project_root)

    if not config then
        vim.notify("Deployment failed: " .. err, vim.log.levels.ERROR)
        return
    end

    local server = nil
    for _, srv in ipairs(config.servers) do
        if srv.name == server_name then
            server = srv
            break
        end
    end

    if not server then
        vim.notify("Server '" .. server_name .. "' not found in .deployment file", vim.log.levels.ERROR)
        return
    end

    -- Get relative path from project root to current file
    local relative_path = vim.fn.fnamemodify(current_file, ":.")
    local filename = vim.fn.fnamemodify(current_file, ":t")

    vim.notify("Deploying " .. filename .. " to " .. server_name .. "...", vim.log.levels.INFO)

    local rsync = require("deployment.rsync")
    rsync.deploy_single_file_to_server(
        config,
        server,
        project_root,
        relative_path,
        function(srv, success, error_msg, duration)
            if success then
                vim.notify(
                    string.format("✓ %s deployed %s successfully (%dms)", srv.name, filename, duration),
                    vim.log.levels.INFO
                )
            else
                vim.notify(
                    string.format(
                        "✗ %s deployment of %s failed: %s",
                        srv.name,
                        filename,
                        error_msg or "Unknown error"
                    ),
                    vim.log.levels.ERROR
                )
            end
        end
    )
end

-- Deploy file by path to all servers
function M.deploy_file_by_path_to_all(file_path, show_progress)
    local project_root = M.get_project_root()

    -- Resolve and validate file path
    local full_path = Path:new(file_path):absolute()
    if not Path:new(full_path):exists() then
        vim.notify("File does not exist: " .. file_path, vim.log.levels.ERROR)
        return
    end

    -- Check if file is within project root
    local project_path = Path:new(project_root):absolute()
    if not full_path:find(project_path, 1, true) then
        vim.notify("File must be within project root: " .. file_path, vim.log.levels.ERROR)
        return
    end

    -- Calculate relative path from project root
    local relative_path = full_path:sub(#project_path + 2) -- +2 to skip trailing slash
    local filename = vim.fn.fnamemodify(full_path, ":t")

    local config, err = M.get_current_config(project_root)

    if not config then
        vim.notify("Deployment failed: " .. err, vim.log.levels.ERROR)
        return
    end

    if #config.servers == 0 then
        vim.notify("No servers configured in .deployment file", vim.log.levels.WARN)
        return
    end

    local results = {}
    local completed = 0
    local total = #config.servers

    if show_progress then
        vim.notify(string.format("Starting deployment of %s to %d server(s)...", filename, total), vim.log.levels.INFO)
    end

    local rsync = require("deployment.rsync")
    for _, server in ipairs(config.servers) do
        rsync.deploy_single_file_to_server(
            config,
            server,
            project_root,
            relative_path,
            function(srv, success, error_msg, duration)
                completed = completed + 1

                table.insert(results, {
                    server = srv,
                    success = success,
                    error = error_msg,
                    duration = duration,
                    filename = filename,
                })

                if show_progress then
                    if success then
                        vim.notify(
                            string.format(
                                "✓ %s deployed %s (%dms) [%d/%d]",
                                srv.name,
                                filename,
                                duration,
                                completed,
                                total
                            ),
                            vim.log.levels.INFO
                        )
                    else
                        vim.notify(
                            string.format(
                                "✗ %s failed to deploy %s: %s [%d/%d]",
                                srv.name,
                                filename,
                                error_msg or "Unknown error",
                                completed,
                                total
                            ),
                            vim.log.levels.ERROR
                        )
                    end
                end

                -- All deployments completed
                if completed == total then
                    M.show_file_deployment_summary(results, filename, show_progress)
                end
            end
        )
    end
end

-- Deploy file by path to specific server
function M.deploy_file_by_path_to_server(file_path, server_name)
    local project_root = M.get_project_root()

    -- Resolve and validate file path
    local full_path = Path:new(file_path):absolute()
    if not Path:new(full_path):exists() then
        vim.notify("File does not exist: " .. file_path, vim.log.levels.ERROR)
        return
    end

    -- Check if file is within project root
    local project_path = Path:new(project_root):absolute()
    if not full_path:find(project_path, 1, true) then
        vim.notify("File must be within project root: " .. file_path, vim.log.levels.ERROR)
        return
    end

    -- Calculate relative path from project root
    local relative_path = full_path:sub(#project_path + 2) -- +2 to skip trailing slash
    local filename = vim.fn.fnamemodify(full_path, ":t")

    local config, err = M.get_current_config(project_root)

    if not config then
        vim.notify("Deployment failed: " .. err, vim.log.levels.ERROR)
        return
    end

    local server = nil
    for _, srv in ipairs(config.servers) do
        if srv.name == server_name then
            server = srv
            break
        end
    end

    if not server then
        vim.notify("Server '" .. server_name .. "' not found in .deployment file", vim.log.levels.ERROR)
        return
    end

    vim.notify("Deploying " .. filename .. " to " .. server_name .. "...", vim.log.levels.INFO)

    local rsync = require("deployment.rsync")
    rsync.deploy_single_file_to_server(
        config,
        server,
        project_root,
        relative_path,
        function(srv, success, error_msg, duration)
            if success then
                vim.notify(
                    string.format("✓ %s deployed %s successfully (%dms)", srv.name, filename, duration),
                    vim.log.levels.INFO
                )
            else
                vim.notify(
                    string.format(
                        "✗ %s deployment of %s failed: %s",
                        srv.name,
                        filename,
                        error_msg or "Unknown error"
                    ),
                    vim.log.levels.ERROR
                )
            end
        end
    )
end

-- Show deployment summary
function M.show_deployment_summary(results, show_summary)
    if not show_summary then
        return
    end

    local successful = 0
    local failed = 0
    local total_time = 0

    for _, result in ipairs(results) do
        if result.success then
            successful = successful + 1
        else
            failed = failed + 1
        end
        total_time = total_time + result.duration
    end

    local avg_time = math.floor(total_time / #results)
    local summary =
        string.format("Deployment complete: %d successful, %d failed (avg: %dms)", successful, failed, avg_time)

    if failed == 0 then
        vim.notify("✓ " .. summary, vim.log.levels.INFO)
    else
        vim.notify("⚠ " .. summary, vim.log.levels.WARN)
    end
end

-- Show file deployment summary
function M.show_file_deployment_summary(results, filename, show_summary)
    if not show_summary then
        return
    end

    local successful = 0
    local failed = 0
    local total_time = 0

    for _, result in ipairs(results) do
        if result.success then
            successful = successful + 1
        else
            failed = failed + 1
        end
        total_time = total_time + result.duration
    end

    local avg_time = math.floor(total_time / #results)
    local summary = string.format(
        "File %s deployment: %d successful, %d failed (avg: %dms)",
        filename,
        successful,
        failed,
        avg_time
    )

    if failed == 0 then
        vim.notify("✓ " .. summary, vim.log.levels.INFO)
    else
        vim.notify("⚠ " .. summary, vim.log.levels.WARN)
    end
end

-- List configured servers
function M.list_servers()
    local project_root = M.get_project_root()
    local config, err, active_name = M.get_current_config(project_root)

    if not config then
        vim.notify("Cannot list servers: " .. err, vim.log.levels.ERROR)
        return
    end

    if #config.servers == 0 then
        vim.notify("No servers configured", vim.log.levels.INFO)
        return
    end

    local lines = { "Configured deployment servers (" .. (active_name or "default") .. "):" }
    for _, server in ipairs(config.servers) do
        local host = server.host or "unknown_host"
        local remote_path = server.remote_path or "unknown_path"
        local local_path = server.local_path or "."
        local name = server.name or "unnamed"
        table.insert(lines, string.format("  • %s: %s -> %s:%s", name, local_path, host, remote_path))
    end

    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

-- Create example .deployment file
function M.create_example_deployment_file(use_multi_config)
    local project_root = M.get_project_root()
    local deployment_file = Path:new(project_root, require("deployment.config").get().deployment_file)

    if deployment_file:exists() then
        vim.notify(".deployment file already exists", vim.log.levels.WARN)
        return
    end

    local example_content = [[# Deployment configuration (YAML format)
# Deploy files to multiple servers using rsync

servers:
  staging:
    host: user@staging.example.com
    remote_path: /var/www/html
    local_path: .

  production:
    host: deploy@prod.example.com
    remote_path: /var/www/html
    local_path: ./dist

  backup:
    host: backup@backup.server.com
    remote_path: /backups/myproject
    local_path: .

# Exclude patterns (in addition to defaults: .git/, .DS_Store, node_modules/)
exclude:
  - "*.log"
  - "tmp/"
  - "*.tmp"
  - "coverage/"
  - ".env*"

# Include patterns (processed before excludes)
include:
  - "important.log"
  - "config/*.production"

# Additional rsync options
options:
  - "--compress-level=6"
  - "--partial"
  - "--progress"
]]

    deployment_file:write(example_content, "w")
    local config_type = use_multi_config and "multi-configuration" or "single configuration"
    vim.notify(
        "Created example " .. config_type .. " .deployment file at: " .. deployment_file.filename,
        vim.log.levels.INFO
    )
end

-- List all available configurations
function M.list_configurations()
    local project_root = M.get_project_root()
    local parser = require("deployment.parser")
    local multi_config, err =
        parser.parse_multi_config_deployment(project_root .. "/" .. require("deployment.config").get().deployment_file)

    if not multi_config then
        vim.notify("Cannot list configurations: " .. err, vim.log.levels.ERROR)
        return
    end

    if not multi_config.configurations or vim.tbl_isempty(multi_config.configurations) then
        vim.notify("No configurations found. This appears to be a single-config deployment file.", vim.log.levels.INFO)
        return
    end

    local lines = { "Available deployment configurations:" }
    for config_name, config in pairs(multi_config.configurations) do
        local active_marker = (config_name == multi_config.active) and " (active)" or ""
        local server_count = #config.servers
        table.insert(lines, string.format("  • %s: %d server(s)%s", config_name, server_count, active_marker))
    end

    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

-- Set active configuration
function M.set_active_configuration(config_name)
    local project_root = M.get_project_root()
    local deployment_file = Path:new(project_root, require("deployment.config").get().deployment_file)

    if not deployment_file:exists() then
        vim.notify("No .deployment file found", vim.log.levels.ERROR)
        return
    end

    local parser = require("deployment.parser")
    local multi_config, err = parser.parse_multi_config_deployment(deployment_file.filename)
    if not multi_config then
        vim.notify("Cannot parse configurations: " .. err, vim.log.levels.ERROR)
        return
    end

    if not multi_config.configurations or not multi_config.configurations[config_name] then
        vim.notify("Configuration '" .. config_name .. "' not found", vim.log.levels.ERROR)
        return
    end

    -- Read the file and update the active line
    local content = deployment_file:read()
    local lines = vim.split(content, "\n")
    local updated = false

    for i, line in ipairs(lines) do
        if line:match("^active:%s*") then
            lines[i] = "active: " .. config_name
            updated = true
            break
        end
    end

    if not updated then
        -- Insert active line after first comment block or at the beginning
        local insert_pos = 1
        for i, line in ipairs(lines) do
            if not line:match("^#") and vim.trim(line) ~= "" then
                insert_pos = i
                break
            end
        end
        table.insert(lines, insert_pos, "active: " .. config_name)
        table.insert(lines, insert_pos + 1, "")
    end

    deployment_file:write(table.concat(lines, "\n"), "w")
    vim.notify("Active configuration set to: " .. config_name, vim.log.levels.INFO)
end

-- Debug deployment file parsing
function M.debug_parse()
    local project_root = M.get_project_root()
    vim.notify("Project root: " .. project_root, vim.log.levels.INFO)

    local parser = require("deployment.parser")
    local deployment_file_path = project_root .. "/" .. require("deployment.config").get().deployment_file

    -- Test multi-config parsing
    local multi_config, multi_err = parser.parse_multi_config_deployment(deployment_file_path)
    if multi_config then
        vim.notify("Multi-config parsing SUCCESS", vim.log.levels.INFO)
        vim.notify("Active: " .. (multi_config.active or "nil"), vim.log.levels.INFO)
        local config_count = multi_config.configurations and vim.tbl_count(multi_config.configurations) or 0
        vim.notify("Found " .. config_count .. " configurations", vim.log.levels.INFO)

        if multi_config.configurations then
            for name, config in pairs(multi_config.configurations) do
                local server_count = config.servers and #config.servers or 0
                vim.notify("  - " .. name .. ": " .. server_count .. " servers", vim.log.levels.INFO)
            end
        end
    else
        vim.notify("Multi-config parsing FAILED: " .. (multi_err or "unknown"), vim.log.levels.ERROR)
    end

    -- Test current config
    local config, err, active_name = M.get_current_config(project_root)
    if config then
        vim.notify("Current config SUCCESS: " .. (active_name or "default"), vim.log.levels.INFO)
        vim.notify("Servers in current config: " .. #config.servers, vim.log.levels.INFO)
    else
        vim.notify("Current config FAILED: " .. (err or "unknown"), vim.log.levels.ERROR)
    end
end

-- Lualine component for deployment status
function M.lualine_component()
    return {
        function()
            local project_root = M.get_project_root()
            local parser = require("deployment.parser")
            local multi_config, _ = parser.parse_multi_config_deployment(
                project_root .. "/" .. require("deployment.config").get().deployment_file
            )

            if multi_config and multi_config.active then
                return "󰒋 " .. multi_config.active
            end

            -- Fallback: check if there's a single config deployment
            local single_config, _ = parser.parse_deployment_config(
                project_root .. "/" .. require("deployment.config").get().deployment_file
            )
            if single_config and single_config.servers and #single_config.servers > 0 then
                return "󰒋 deploy"
            end

            return ""
        end,
        color = { fg = "#7aa2f7" },
    }
end

-- Setup function for the plugin
function M.setup(opts)
    -- Setup configuration
    require("deployment.config").setup(opts)

    -- Setup commands
    require("deployment.commands").setup_commands()

    -- Setup keymaps (optional)
    if opts and opts.keymaps ~= false then
        require("deployment.commands").setup_keymaps()
    end

    -- Make module globally available for backwards compatibility
    _G.Deployment = M
end

return M

