# deployment.nvim

A Neovim plugin for deploying files to multiple servers using rsync. Replicates JetBrains IDE deployment functionality with parallel deployment support.

## Features

- 🚀 **Parallel Deployments**: Deploy to multiple servers simultaneously
- 📁 **File-level Deployments**: Deploy individual files or entire projects
- 🔧 **Flexible Configuration**: Support for both single and multi-configuration setups
- 🎯 **rsync Integration**: Uses rsync for efficient file synchronization
- 📊 **Progress Tracking**: Real-time deployment progress and summaries
- ⚡ **Fast Performance**: Asynchronous operations with timeout support
- 🔍 **Debug Mode**: Built-in debugging for troubleshooting

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "dmbhatti/deployment.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    -- Optional: for better key binding descriptions
    "folke/which-key.nvim",
  },
  config = function()
    require("deployment").setup({
      -- Optional configuration
      keymaps = true, -- Enable default keymaps (default: true)
      debug = false,  -- Enable debug mode (default: false)
    })
  end,
  cmd = {
    "Deploy", "DeployAll", "DeployList", "DeployInit", 
    "DeployFile", "DeployFileAll", "DeployFilePath",
    "DeployConfigs", "DeploySetActive", "DeployDebug"
  },
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "dmbhatti/deployment.nvim",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("deployment").setup()
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'dmbhatti/deployment.nvim'
```

Then in your `init.lua`:
```lua
require("deployment").setup()
```

## Configuration

### Plugin Configuration

```lua
require("deployment").setup({
  -- Deployment file name (default: ".deployment")
  deployment_file = ".deployment",
  
  -- Default rsync options (default: {"-avz", "--exclude=.git/", "--exclude=.DS_Store", "--exclude=node_modules/"})
  rsync_options = {
    "-avz",
    "--exclude=.git/",
    "--exclude=.DS_Store",
    "--exclude=node_modules/",
  },
  
  -- Maximum parallel jobs (default: 5)
  parallel_jobs = 5,
  
  -- Timeout in milliseconds (default: 30000)
  timeout = 30000,
  
  -- Enable debug mode (default: false)
  debug = false,
  
  -- Delete remote files that don't exist locally (default: false)
  delete_remote_files = false,
  
  -- Enable default keymaps (default: true)
  keymaps = true,
})
```

### Deployment File Configuration

Create a `.deployment` file in your project root:

#### Simple Configuration

```yaml
# Deployment configuration (YAML format)
servers:
  staging:
    host: user@staging.example.com
    remote_path: /var/www/html
    local_path: .
  
  production:
    host: deploy@prod.example.com
    remote_path: /var/www/html
    local_path: ./dist

# Exclude patterns
exclude:
  - "*.log"
  - "tmp/"
  - ".env*"

# Include patterns (processed before excludes)
include:
  - "important.log"

# Additional rsync options
options:
  - "--compress-level=6"
  - "--partial"
```

#### Multi-Configuration Setup

```yaml
# Multi-configuration deployment file
active: development

configurations:
  development:
    servers:
      dev1:
        host: dev@dev1.example.com
        remote_path: /var/www/dev
        local_path: .
      dev2:
        host: dev@dev2.example.com
        remote_path: /var/www/dev
        local_path: .
    exclude:
      - "*.log"
      - "node_modules/"
    options:
      - "--dry-run"

  production:
    servers:
      prod1:
        host: deploy@prod1.example.com
        remote_path: /var/www/html
        local_path: ./dist
      prod2:
        host: deploy@prod2.example.com
        remote_path: /var/www/html
        local_path: ./dist
    exclude:
      - "*.log"
      - "*.tmp"
    options:
      - "--compress-level=9"
```

## Commands

| Command | Description |
|---------|-------------|
| `:Deploy [server]` | Deploy to specific server or all servers |
| `:DeployAll` | Deploy to all configured servers |
| `:DeployList` | List configured deployment servers |
| `:DeployInit [multi]` | Create example .deployment file |
| `:DeployFile [server]` | Deploy current file to server(s) |
| `:DeployFileAll` | Deploy current file to all servers |
| `:DeployFilePath <path> [server]` | Deploy specific file by path |
| `:DeployConfigs` | List all configurations (multi-config) |
| `:DeploySetActive <config>` | Set active configuration |
| `:DeployDebug` | Toggle debug mode |
| `:DeployDebugParse` | Debug deployment file parsing |

## Keymaps

Default keymaps (prefix: `<leader>t`):

| Keymap | Command | Description |
|--------|---------|-------------|
| `<leader>ta` | Deploy to all servers | Full deployment to all configured servers |
| `<leader>ts` | Deploy to specific server | Select server interactively |
| `<leader>tl` | List servers | Show configured deployment servers |
| `<leader>ti` | Create .deployment file | Interactive creation |
| `<leader>tf` | Deploy current file (all) | Deploy current file to all servers |
| `<leader>tF` | Deploy current file (specific) | Select server for current file |
| `<leader>tc` | List configurations | Show available configurations |
| `<leader>tC` | Set active configuration | Select active configuration |

To disable default keymaps:
```lua
require("deployment").setup({
  keymaps = false
})
```

## Usage Examples

### Basic Deployment

1. Create a `.deployment` file in your project root:
   ```bash
   :DeployInit
   ```

2. Edit the file to configure your servers

3. Deploy to all servers:
   ```bash
   :DeployAll
   ```
   or use the keymap: `<leader>ta`

4. Deploy to a specific server:
   ```bash
   :Deploy staging
   ```
   or use the keymap: `<leader>ts`

### File-Level Deployment

Deploy just the current file:
```bash
:DeployFile
# or
<leader>tf
```

Deploy a specific file:
```bash
:DeployFilePath src/main.js staging
```

### Multi-Configuration

1. Create a multi-config deployment file:
   ```bash
   :DeployInit multi
   ```

2. List available configurations:
   ```bash
   :DeployConfigs
   ```

3. Set active configuration:
   ```bash
   :DeploySetActive production
   ```

4. Deploy using active configuration:
   ```bash
   :DeployAll
   ```

## Integration

### Lualine Integration

Add deployment status to your lualine:

```lua
require('lualine').setup {
  sections = {
    lualine_x = {
      require("deployment").lualine_component(),
      'encoding',
      'fileformat',
      'filetype'
    },
  }
}
```

### Status Line Integration

For other status line plugins:

```lua
local deployment_status = require("deployment").lualine_component()
```

## Requirements

- Neovim >= 0.7.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- `rsync` command available in PATH
- SSH access to target servers

## FAQ

### How do I set up SSH key authentication?

Make sure your SSH key is added to the target servers and your SSH agent is running:

```bash
ssh-add ~/.ssh/your_key
ssh user@your-server.com  # Test connection
```

### How do I exclude sensitive files?

Add patterns to the `exclude` section in your `.deployment` file:

```yaml
exclude:
  - ".env*"
  - "*.secret"
  - "config/database.yml"
  - "node_modules/"
```

### How do I debug deployment issues?

1. Enable debug mode:
   ```bash
   :DeployDebug
   ```

2. Test deployment file parsing:
   ```bash
   :DeployDebugParse
   ```

3. Check the deployment file syntax and server connectivity

### Can I use different local paths for different servers?

Yes! Configure different `local_path` for each server:

```yaml
servers:
  staging:
    host: user@staging.com
    remote_path: /var/www/html
    local_path: .
  
  production:
    host: user@prod.com
    remote_path: /var/www/html
    local_path: ./dist  # Different local path
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License. See `LICENSE` file for details.

## Similar Projects

- [transfer.nvim](https://github.com/coffebar/transfer.nvim) - Similar rsync-based deployment
- [vim-rsync](https://github.com/kenn7/vim-rsync) - Vim plugin for rsync