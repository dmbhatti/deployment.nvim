-- Luacheck configuration file
std = luajit
cache = true

-- Global objects defined by Neovim
read_globals = {
  "vim",
}

-- Allow vim global in all files
globals = {
  "vim",
}

-- Ignore some common warnings
ignore = {
  "212/_.*", -- unused argument, for vars with "_" prefix
  "214", -- unused variable
  "121", -- setting read-only global variable
  "122", -- setting read-only field of global variable
}

-- Files to check
include_files = {
  "lua/**/*.lua",
}

-- Exclude directories
exclude_files = {
  "lua/**/*_spec.lua", -- test files if we add them later
}