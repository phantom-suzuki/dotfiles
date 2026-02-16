local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.automatically_reload_config = true
config.use_ime = true

-- Load modules
require("appearance").apply(config)
require("tabs").apply(config)

-- Keybinds
config.disable_default_key_bindings = true
config.leader = { key = "q", mods = "CTRL", timeout_milliseconds = 2000 }
local keybinds = require("keybinds")
config.keys = keybinds.keys
config.key_tables = keybinds.key_tables

-- Setup event handlers
require("tabs").setup()
require("statusbar").setup()
require("events").setup()

-- Plugins (resurrect)
local resurrect = wezterm.plugin.require("https://github.com/MLFlexer/resurrect.wezterm")
resurrect.state_manager.periodic_save()

return config
