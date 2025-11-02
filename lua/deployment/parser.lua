-- YAML parser module for deployment.nvim
local M = {}

-- Simple YAML parser for .deployment file
local function parse_yaml_value(value)
    if not value then
        return nil
    end

    local trimmed = vim.trim(value)

    -- Handle quoted strings
    if trimmed:match('^".*"$') or trimmed:match("^'.*'$") then
        return trimmed:sub(2, -2)
    end

    -- Handle boolean values
    if trimmed:lower() == "true" then
        return true
    end
    if trimmed:lower() == "false" then
        return false
    end

    -- Handle numbers
    local num = tonumber(trimmed)
    if num then
        return num
    end

    return trimmed
end

-- Simple YAML-like parser for deployment configuration
local function parse_simple_yaml(content)
    local result = {}
    local lines = vim.split(content, "\n")
    local stack = { { table = result, indent = -1 } }

    for _, line in ipairs(lines) do
        -- Skip empty lines and comments
        if not (line:match("^%s*$") or line:match("^%s*#")) then
            local indent = #line:match("^%s*")
            local trimmed = vim.trim(line)

            -- Pop stack to correct level
            while #stack > 1 and stack[#stack].indent >= indent do
                table.remove(stack)
            end

            local current = stack[#stack].table

            if trimmed:match("^(.-):%s*$") then
                -- Key without value (starts a new table)
                local key = trimmed:match("^(.-):%s*$")
                current[key] = {}
                table.insert(stack, { table = current[key], indent = indent })
            elseif trimmed:match("^(.-):%s*(.+)$") then
                -- Key with value
                local key, value = trimmed:match("^(.-):%s*(.+)$")
                current[key] = parse_yaml_value(value)
            elseif trimmed:match("^%-%s*(.+)$") then
                -- Array item
                local value = trimmed:match("^%-%s*(.+)$")
                table.insert(current, parse_yaml_value(value))
            end
        end
    end

    return result
end

-- Parse multi-configuration deployment file
function M.parse_multi_config_deployment(deployment_file_path)
    local Path = require("plenary.path")
    local deployment_file = Path:new(deployment_file_path)

    if not deployment_file:exists() then
        return nil, "No .deployment file found at: " .. deployment_file_path
    end

    local content = deployment_file:read()
    if not content then
        return nil, "Could not read .deployment file"
    end

    local parsed = parse_simple_yaml(content)

    if not parsed.configurations then
        return nil, "No configurations found in deployment file"
    end

    -- Convert servers from hash to array format
    for _config_name, config in pairs(parsed.configurations) do
        if config.servers then
            local servers_array = {}
            for server_name, server_props in pairs(config.servers) do
                local server = {
                    name = server_name,
                    host = server_props.host,
                    remote_path = server_props.remote_path,
                    local_path = server_props.local_path or ".",
                }
                table.insert(servers_array, server)
            end
            config.servers = servers_array
        end

        -- Ensure other sections exist
        config.exclude = config.exclude or {}
        config.include = config.include or {}
        config.options = config.options or {}
    end

    return {
        configurations = parsed.configurations,
        active = parsed.active,
    }, nil
end

-- Parse deployment configuration file (legacy single config support)
function M.parse_deployment_config(deployment_file_path)
    local Path = require("plenary.path")
    local deployment_file = Path:new(deployment_file_path)
    local config = require("deployment.config")

    if not deployment_file:exists() then
        return nil, "No .deployment file found at: " .. deployment_file_path
    end

    local content = deployment_file:read()
    if not content then
        return nil, "Could not read .deployment file"
    end

    local result = {
        servers = {},
        exclude = {},
        include = {},
        options = {},
    }

    local current_section = nil
    local current_server = nil

    for line in content:gmatch("[^\n]+") do
        local trimmed = vim.trim(line)

        -- Skip empty lines and comments
        if trimmed ~= "" and not trimmed:match("^#") then
            -- Check for main sections
            if trimmed == "servers:" then
                current_section = "servers"
            elseif trimmed == "exclude:" then
                current_section = "exclude"
            elseif trimmed == "include:" then
                current_section = "include"
            elseif trimmed == "options:" then
                current_section = "options"
            elseif current_section == "servers" then
                -- Handle server entries
                local server_name = trimmed:match("^%s*([%w_%-]+):$")
                if server_name then
                    current_server = {
                        name = server_name,
                        host = nil,
                        remote_path = nil,
                        local_path = ".",
                    }
                    table.insert(result.servers, current_server)
                elseif current_server then
                    -- Parse server properties
                    if config.get().debug then
                        print(string.format("DEBUG: Parsing line: '%s'", trimmed))
                    end

                    local key, value = trimmed:match("^%s+([%w_]+):%s*(.*)")
                    if key and value then
                        if config.get().debug then
                            print(string.format("DEBUG: Found property '%s' = '%s'", key, value))
                        end
                        current_server[key] = parse_yaml_value(value)
                    else
                        -- Try simpler pattern
                        local simple_key, simple_value = trimmed:match("([%w_]+):%s*(.*)")
                        if simple_key and simple_value then
                            current_server[simple_key] = parse_yaml_value(simple_value)
                        end
                    end
                end
            elseif current_section == "exclude" then
                -- Handle exclude patterns
                local pattern = trimmed:match("^%s*-%s*(.+)")
                if pattern then
                    table.insert(result.exclude, parse_yaml_value(pattern))
                end
            elseif current_section == "include" then
                -- Handle include patterns
                local pattern = trimmed:match("^%s*-%s*(.+)")
                if pattern then
                    table.insert(result.include, parse_yaml_value(pattern))
                end
            elseif current_section == "options" then
                -- Handle rsync options
                local option = trimmed:match("^%s*-%s*(.+)")
                if option then
                    table.insert(result.options, parse_yaml_value(option))
                end
            end
        end
    end

    return result, nil
end

return M

