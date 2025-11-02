-- Commands and keymaps for deployment.nvim
local M = {}

local deployment = require("deployment")

-- Get server completion
local function get_server_completion()
    local project_root = deployment.get_project_root()
    local config, _ = deployment.get_current_config(project_root)

    if not config or #config.servers == 0 then
        return {}
    end

    local server_names = {}
    for _, server in ipairs(config.servers) do
        table.insert(server_names, server.name)
    end

    return server_names
end

-- Get configuration completion
local function get_config_completion()
    local project_root = deployment.get_project_root()
    local parser = require("deployment.parser")
    local multi_config, _ =
        parser.parse_multi_config_deployment(project_root .. "/" .. require("deployment.config").get().deployment_file)

    if not multi_config or not multi_config.configurations then
        return {}
    end

    local config_names = {}
    for config_name, _ in pairs(multi_config.configurations) do
        table.insert(config_names, config_name)
    end

    return config_names
end

-- Get file completion
local function get_file_completion()
    local project_root = deployment.get_project_root()

    -- Get all files in project (excluding common build/temp directories)
    local files = {}
    local find_cmd = "find '" .. project_root .. "' -type f"
        .. " -not -path '*/node_modules/*'"
        .. " -not -path '*/.git/*'"
        .. " -not -path '*/dist/*'"
        .. " -not -path '*/build/*'"
        .. " -not -path '*/target/*'"
        .. " 2>/dev/null"
    local handle = io.popen(find_cmd)

    if handle then
        for file in handle:lines() do
            -- Make path relative to project root
            local relative = file:sub(#project_root + 2)
            if relative and relative ~= "" then
                table.insert(files, relative)
            end
        end
        handle:close()
    end

    return files
end

-- Setup user commands
function M.setup_commands()
    vim.api.nvim_create_user_command("DeployAll", function()
        deployment.deploy_all(true)
    end, { desc = "Deploy to all configured servers" })

    vim.api.nvim_create_user_command("Deploy", function(opts)
        if opts.args == "" then
            deployment.deploy_all(true)
        else
            deployment.deploy_to_specific_server(opts.args)
        end
    end, {
        desc = "Deploy to specific server or all servers",
        nargs = "?",
        complete = get_server_completion,
    })

    vim.api.nvim_create_user_command("DeployList", function()
        deployment.list_servers()
    end, { desc = "List configured deployment servers" })

    vim.api.nvim_create_user_command("DeployInit", function(opts)
        local use_multi_config = opts.args == "multi" or opts.args == "m"
        deployment.create_example_deployment_file(use_multi_config)
    end, {
        desc = "Create example .deployment file (add 'multi' for multi-config)",
        nargs = "?",
    })

    vim.api.nvim_create_user_command("DeployDebug", function()
        local config = require("deployment.config")
        config.set("debug", not config.get().debug)
        vim.notify("Deployment debug mode: " .. (config.get().debug and "ON" or "OFF"), vim.log.levels.INFO)
    end, { desc = "Toggle deployment debug mode" })

    vim.api.nvim_create_user_command("DeployFile", function(opts)
        if opts.args == "" then
            deployment.deploy_current_file_to_all(true)
        else
            deployment.deploy_current_file_to_server(opts.args)
        end
    end, {
        desc = "Deploy current file to specific server or all servers",
        nargs = "?",
        complete = get_server_completion,
    })

    vim.api.nvim_create_user_command("DeployFileAll", function()
        deployment.deploy_current_file_to_all(true)
    end, { desc = "Deploy current file to all servers" })

    vim.api.nvim_create_user_command("DeployFilePath", function(opts)
        local args = vim.split(opts.args, "%s+")
        if #args == 0 or args[1] == "" then
            vim.notify("Please specify a file path", vim.log.levels.WARN)
            return
        end

        local file_path = args[1]
        local server_name = args[2]

        if server_name then
            deployment.deploy_file_by_path_to_server(file_path, server_name)
        else
            deployment.deploy_file_by_path_to_all(file_path, true)
        end
    end, {
        desc = "Deploy file by path to all servers or specific server",
        nargs = "+",
        complete = function(arg_lead, cmd_line, _cursor_pos)
            local args = vim.split(cmd_line, "%s+")
            local arg_count = #args

            -- First argument: file path
            if arg_count <= 2 then
                local files = get_file_completion()
                local matches = {}
                for _, file in ipairs(files) do
                    if file:find(arg_lead, 1, true) == 1 then
                        table.insert(matches, file)
                    end
                end
                return matches
            -- Second argument: server name
            elseif arg_count == 3 then
                local servers = get_server_completion()
                local matches = {}
                for _, server in ipairs(servers) do
                    if server:find(arg_lead, 1, true) == 1 then
                        table.insert(matches, server)
                    end
                end
                return matches
            end

            return {}
        end,
    })

    vim.api.nvim_create_user_command("DeployConfigs", function()
        deployment.list_configurations()
    end, { desc = "List all deployment configurations" })

    vim.api.nvim_create_user_command("DeploySetActive", function(opts)
        if opts.args == "" then
            vim.notify("Please specify a configuration name", vim.log.levels.WARN)
            return
        end
        deployment.set_active_configuration(opts.args)
    end, {
        desc = "Set active deployment configuration",
        nargs = 1,
        complete = get_config_completion,
    })

    vim.api.nvim_create_user_command("DeployDebugParse", function()
        deployment.debug_parse()
    end, { desc = "Debug deployment file parsing" })
end

-- Setup keymaps (optional, only if which-key is available)
function M.setup_keymaps()
    -- Check if which-key is available
    local ok, wk = pcall(require, "which-key")
    if ok then
        wk.add({
            { "<leader>t", group = "deployment", icon = "󰒋" },
            { "<leader>ta", desc = "Deploy to all servers", icon = "󰒋" },
            { "<leader>ts", desc = "Deploy to specific server", icon = "󰒓" },
            { "<leader>tl", desc = "List deployment servers", icon = "󰒉" },
            { "<leader>ti", desc = "Create .deployment file", icon = "󰒅" },
            { "<leader>tf", desc = "Deploy current file to all servers", icon = "󰈙" },
            { "<leader>tF", desc = "Deploy current file to specific server", icon = "󰈚" },
            { "<leader>tc", desc = "List configurations", icon = "󰒉" },
            { "<leader>tC", desc = "Set active configuration", icon = "󰒓" },
        })
    end

    -- Setup actual keymaps
    vim.keymap.set("n", "<leader>ta", function()
        deployment.deploy_all(true)
    end, { desc = "Deploy to all servers" })

    vim.keymap.set("n", "<leader>ts", function()
        local servers = get_server_completion()
        if #servers == 0 then
            vim.notify("No servers configured", vim.log.levels.WARN)
            return
        end

        vim.ui.select(servers, {
            prompt = "Select server to deploy to:",
        }, function(choice)
            if choice then
                deployment.deploy_to_specific_server(choice)
            end
        end)
    end, { desc = "Deploy to specific server" })

    vim.keymap.set("n", "<leader>tl", function()
        deployment.list_servers()
    end, { desc = "List deployment servers" })

    vim.keymap.set("n", "<leader>ti", function()
        vim.ui.select({ "Single configuration", "Multi-configuration" }, {
            prompt = "Select deployment file type:",
        }, function(choice)
            if choice then
                local use_multi_config = choice == "Multi-configuration"
                deployment.create_example_deployment_file(use_multi_config)
            end
        end)
    end, { desc = "Create .deployment file" })

    vim.keymap.set("n", "<leader>tf", function()
        deployment.deploy_current_file_to_all(true)
    end, { desc = "Deploy current file to all servers" })

    vim.keymap.set("n", "<leader>tF", function()
        local servers = get_server_completion()
        if #servers == 0 then
            vim.notify("No servers configured", vim.log.levels.WARN)
            return
        end

        vim.ui.select(servers, {
            prompt = "Select server to deploy current file to:",
        }, function(choice)
            if choice then
                deployment.deploy_current_file_to_server(choice)
            end
        end)
    end, { desc = "Deploy current file to specific server" })

    vim.keymap.set("n", "<leader>tc", function()
        deployment.list_configurations()
    end, { desc = "List configurations" })

    vim.keymap.set("n", "<leader>tC", function()
        local configs = get_config_completion()
        if #configs == 0 then
            vim.notify("No configurations found", vim.log.levels.WARN)
            return
        end

        vim.ui.select(configs, {
            prompt = "Select active configuration:",
        }, function(choice)
            if choice then
                deployment.set_active_configuration(choice)
            end
        end)
    end, { desc = "Set active configuration" })
end

return M

