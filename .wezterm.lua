
local wezterm = require 'wezterm'
local act = wezterm.action


function get_appearance()
  if wezterm.gui then
    return wezterm.gui.get_appearance()
  end
  return 'Dark'
end

function scheme_for_appearance(appearance)
  if appearance:find 'Dark' then
    return 'Default (dark) (terminal.sexy)' --'Builtin Solarized Dark'
  else
    return 'Ef-Spring'
  end
end

function shellexpand(path)
    local home = os.getenv("HOME")
    return path:gsub("^~", home)
end

-- Function to format directory path for display
function format_directory_path(file_path)
  local home = os.getenv("HOME")
  local cwd = file_path

  -- Check if it's a string and has a proper format
  if type(cwd) ~= "string" then
    return "unknown"
  end

  -- For file:// URLs (which WezTerm often uses)
  if cwd:find("^file://") then
    -- Remove the file:// prefix
    cwd = cwd:gsub("^file://", "")
  end

  -- If the path is within home directory
  if cwd:find("^" .. home) then
    -- Replace home path with ~
    cwd = "~" .. cwd:sub(#home + 1)
  end

  -- Get last two components
  local components = {}
  for component in cwd:gmatch("[^/]+") do
    table.insert(components, component)
  end

  if #components >= 2 then
    -- If the second-to-last component is "~", only show last component
    if components[#components - 1] == "~" then
      return "~/" .. components[#components]
    else
      -- Otherwise show last two components
      return components[#components - 1] .. "/" .. components[#components]
    end
  elseif #components == 1 then
    return components[1]
  else
    return "/"
  end
end


local config = wezterm.config_builder()
-- Just set a specific theme and nothing else

local sessionizer = wezterm.plugin.require "https://github.com/mikkasendke/sessionizer.wezterm"
sessionizer.config = {
    paths = {
        shellexpand("~/work/mono-1"),
        shellexpand("~/work/mono-2"),
        shellexpand("~/work/mono-3"),
    },
    command_options = {
        fd_path = '/opt/homebrew/bin/fd',
    },
}
sessionizer.apply_to_config(config, true)

-- Set color scheme based on system appearance
config.color_scheme = scheme_for_appearance(get_appearance())

-- config.term = "wezterm"
config.enable_kitty_graphics = false
config.adjust_window_size_when_changing_font_size = false

local function txt_fg_fmt(color, text)
    -- Each format item should have only one key
    return {
        { Foreground = { Color = color } }, -- First set the foreground color
        { Text = text },                    -- Then add the text
        "ResetAttributes"                   -- Then reset attributes
    }
end

local function extend_table(target, source)
  for _, v in ipairs(source) do
    table.insert(target, v)
  end
  return target  -- Return the target for chaining if desired
end

-- Process color mapping (declarative approach)
local process_colors = {
  emacs = "orange",
  emacsclient = "orange",
  git = "purple"
}

-- Directory prefix color mapping (declarative approach)
local dir_name_colors = {
    ['mono-1'] = 'red',
    ['mono-2'] = 'white',
    ['mono-3'] = 'blue',
    ["apps"] = "cyan",
    ["libs"] = "yellow",
    ["mops"] = 'green',
}

-- Format directory with colored prefixes if applicable
local function format_colored_directory(dir_path)
  local result = {}
  local parts = {}

  -- Split path into components
  for part in dir_path:gmatch("([^/]+)") do
    table.insert(parts, part)
  end

  -- Process each part with coloring as needed
  for i, part in ipairs(parts) do
    if i > 1 then
      table.insert(result, {Text = "/"})
    end

    if dir_name_colors[part] then
      extend_table(result, txt_fg_fmt(dir_name_colors[part], part))
    else
      table.insert(result, {Text = part})
    end
  end

  return result
end


local function format_tab_title(tab, tabs, panes, config, hover, max_width)
  local process = tab.active_pane.foreground_process_name
  local dir = "unknown"

  -- Extract just the process name without path
  process = process:gsub("^.*/([^/]+)$", "%1")

  if process == "mise" or process == "bash" then
    process = "xonsh"
  end

  if tab.active_pane and tab.active_pane.current_working_dir then
    dir = format_directory_path(tab.active_pane.current_working_dir.path)
  end

  local tab_format_items = { { Text = tostring(tab.tab_index + 1) .. " | "} }

  -- Apply process coloring based on lookup table
  if process_colors[process] then
    extend_table(tab_format_items, txt_fg_fmt(process_colors[process], process))
  else
    table.insert(tab_format_items, { Text = process })
  end

  table.insert(tab_format_items, { Text = ": " })

  -- Apply directory coloring
  extend_table(tab_format_items, format_colored_directory(dir))

  return tab_format_items
end

wezterm.on('format-tab-title', format_tab_title)

-- Set backtick as leader key
config.leader = { key = '`', mods = '', timeout_milliseconds = 1000 }

-- Define keyboard shortcuts that use the leader
config.keys = {
    -- Add iTerm-like fullscreen toggle
    { key = '0', mods = 'CMD|SHIFT', action = act.ToggleFullScreen },

    -- Sessions (Workspaces)
    { key = 's', mods = 'LEADER', action = act.ShowLauncherArgs { flags = 'WORKSPACES' } },
    { key = 'w', mods = 'LEADER', action = sessionizer.show },
    -- create new workspace with name
    { key = 'n', mods = 'LEADER', action = act.PromptInputLine {
          description = 'Enter name for new workspace',
          action = wezterm.action_callback(function(window, pane, line)
                  if line then
                      -- Get current working directory
                      local cwd = pane:get_current_working_dir()

                      -- Switch to a new workspace with the specified name and cwd
                      window:perform_action(
                          act.SwitchToWorkspace {
                              name = line,
                              spawn = {
                                  cwd = cwd.file_path,
                              },
                          },
                          pane
                      )
                  end
          end),
    }},

    -- Rename current workspace
    { key = 'r', mods = 'LEADER', action = act.PromptInputLine
      {
          description = 'Enter new name for current workspace',
          action = wezterm.action_callback(
              function(window, pane, line)
                  if line then
                      window:perform_action(
                          act.RenameWorkspace {
                              name = line,
                          },
                          pane
                      )
                  end
              end
          )
      }
    },

    -- Tabs
    { key = 'c', mods = 'LEADER', action = act.SpawnTab 'DefaultDomain' },
    { key = 'k', mods = 'LEADER', action = act.CloseCurrentTab { confirm = false } },
    { key = '[', mods = 'LEADER', action = act.ActivateTabRelative(-1) },
    { key = ']', mods = 'LEADER', action = act.ActivateTabRelative(1) },
    { key = '1', mods = 'LEADER', action = act.ActivateTab(0) },
    { key = '2', mods = 'LEADER', action = act.ActivateTab(1) },
    { key = '3', mods = 'LEADER', action = act.ActivateTab(2) },
    { key = '4', mods = 'LEADER', action = act.ActivateTab(3) },
    { key = '5', mods = 'LEADER', action = act.ActivateTab(4) },
    { key = '6', mods = 'LEADER', action = act.ActivateTab(5) },
    { key = '7', mods = 'LEADER', action = act.ActivateTab(6) },
    { key = '8', mods = 'LEADER', action = act.ActivateTab(7) },
    { key = '8', mods = 'LEADER', action = act.ActivateTab(7) },
    { key = '9', mods = 'LEADER', action = act.ActivateTab(8) },
    { key = '0', mods = 'LEADER', action = act.ActivateTab(9) },

    -- Make backtick+backtick send a literal backtick
    { key = '`', mods = 'LEADER', action = act.SendKey { key = '`' } },
}

-- Add translucency
config.window_background_opacity = 0.85
config.macos_window_background_blur = 20
config.window_decorations = "RESIZE"
config.tab_bar_at_bottom = true

return config
