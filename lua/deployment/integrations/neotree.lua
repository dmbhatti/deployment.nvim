local M = {}

-- Normal mode: deploy node under cursor
function M.deploy_node(state)
    local node = state.tree:get_node()
    if not node or node.type == "message" then
        return
    end
    require("deployment").deploy_file_by_path_to_all(node:get_id(), true)
end

-- Visual mode: deploy all selected nodes (same signature as neo-tree visual commands)
function M.deploy_node_visual(state, selected_nodes)
    local deploy = require("deployment")
    for _, node in ipairs(selected_nodes) do
        if node.type ~= "message" then
            deploy.deploy_file_by_path_to_all(node:get_id(), true)
        end
    end
end

function M.setup()
    -- No-op: keymaps are registered via neo-tree's window.mappings config
end

return M
