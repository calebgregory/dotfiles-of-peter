
local wezterm = require 'wezterm'
local act = wezterm.action


function get_appearance()
    if wezterm.gui then
        return wezterm.gui.get_appearance()
    end
    return 'Dark'
end

function scheme_for_appearance(appearance)
  -- https://wezterm.org/colorschemes/index.html
    if appearance:find 'Dark' then
        return 'Default (dark) (terminal.sexy)' --'Builtin Solarized Dark'
    else
        return 'Ef-Spring'
    end
end

function shellexpand(path)
    local home = os.getenv("HOME")
    fullpath, n_subs = path:gsub("^~", home)
    return fullpath
end

local function read_paths_from_file(file_path)
    local paths = {}
    local file = io.open(file_path, "r")
    if file then
        for line in file:lines() do
            if line ~= "" then
                table.insert(paths, shellexpand(line))
            end
        end
        file:close()
    end
    return paths
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
    paths = read_paths_from_file(shellexpand("~/.config/wezterm/session-dirs.txt")),
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

-- Simple string hash function (djb2 algorithm)
local function hash_string(str)
    local hash = 5381
    for i = 1, #str do
        hash = ((hash * 33) + string.byte(str, i)) % 2^32
    end
    return hash
end

local high_contrast_colors = {
    "#FF5555", -- Bright Red
    "#50FA7B", -- Bright Green
    "#F1FA8C", -- Bright Yellow
    "#BD93F9", -- Bright Purple
    "#FF79C6", -- Bright Pink
    "#8BE9FD", -- Bright Cyan
    "#FFB86C", -- Bright Orange
    "#FF92DF", -- Light Pink
    "#9AEDFE", -- Light Blue
    "#5AF78E", -- Light Green
    "#F4F99D", -- Light Yellow
    "#CAA9FA", -- Light Purple
    "#FF6E67", -- Light Red
    "#ADEDC8", -- Soft Green
    "#FEA44D"  -- Soft Orange
}

-- Get a deterministic color for a string
local function get_deterministic_color(str)
    local hash = hash_string(str)
    local index = (hash % #high_contrast_colors) + 1
    return high_contrast_colors[index]
end

-- Process color mapping (declarative approach)
local process_colors = {
    emacs = "orange",
    emacsclient = "orange",
    git = "#bb55ff" -- pretty purple
}

-- Directory prefix color mapping (declarative approach)
local dir_name_colors = {
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
            extend_table(result, txt_fg_fmt(get_deterministic_color(part), part))
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

local function get_git_branch(cwd)
  local git_cmd = { "bash", "-c", "cd " .. cwd .. " && git rev-parse --abbrev-ref HEAD" }
  local result, stdout, stderr = wezterm.run_child_process(git_cmd)
  if result then
    branch_name = stdout:gsub("%s+$", "") -- Trim trailing whitespace
    return branch_name
  end
  return nil
end

local function update_status(window, pane)
  local cwd = pane:get_current_working_dir()
  if cwd then
    -- Extract the path (handling file:// URIs)
    cwd = cwd.file_path or cwd
    local branch = get_git_branch(cwd)
    if branch then
      window:set_right_status(
        wezterm.format({
          { Foreground = { Color = 'limegreen' } },
          { Text = branch.." " },
        })
      )
    else
      window:set_right_status("") -- Clears the status if not in a git repo
    end
  else
    window:set_right_status("")
  end
end

-- Hook into the right status update event
wezterm.on("update-status", update_status)

config.leader = { key = 'x', mods = 'CTRL', timeout_milliseconds = 1000 }

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

    -- Panes
    { key = '"', mods = "LEADER", action = wezterm.action.SplitVertical { domain = "CurrentPaneDomain" } },
    { key = '%', mods = "LEADER", action = wezterm.action.SplitHorizontal { domain = "CurrentPaneDomain" } },
    { key = "h", mods = "LEADER", action = wezterm.action.ActivatePaneDirection("Prev") },
    { key = "l", mods = "LEADER", action = wezterm.action.ActivatePaneDirection("Next") },

    { key = ' ', mods = 'LEADER', action = act.ActivateCopyMode },
}

-- Add translucency
config.window_background_opacity = 0.98
config.macos_window_background_blur = 20
config.window_decorations = "RESIZE"
config.tab_bar_at_bottom = true
config.status_update_interval = 2500
-- config.use_fancy_tab_bar = true
config.window_frame = {
    font = wezterm.font('FiraCode'),
    font_size = 12,
}

return config
