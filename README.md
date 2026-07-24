# Editor

A code editor written in the [ol](https://github.com/ejrich/lang) language.

## Overview

The main goal of this editor is to be everything you need while being extremely fast.

### Features

* Vim Keybindings
* Source Control (git, p4, svn)
* Terminal
* Debugger (requires lldb)
* Workspaces
* File Finder
* Search
* Hex View for binary files
* Coding Agent Support (coming soon!)

## Workspaces

You can open up to 10 workspaces per window. A workspace corresponds to a regular directory and will have its own buffers, commands from each localsettings file, terminal, and debugger

## Configuration

After first start, there will be a `settings` and 'keybinds` file created in `$HOME/Documents/Editor`

The `settings` file has the following options:

* tab_size
* window_width
* window_height
* font
* font_size
* font_color
* line_number_color
* current_line_color
* cursor_color
* cursor_font_color
* visual_font_color
* background_color
* background_transparency
* normal_mode_color
* insert_mode_color
* visual_mode_color
* string_color
* char_color
* comment_color
* syntax_red_color
* syntax_green_color
* syntax_yellow_color
* syntax_blue_color
* syntax_purple_color
* syntax_aqua_color
* syntax_orange_color
* reactive_render

> All *_color settings are RGB hex values

The `keybinds` file has a command and an associated keybind in the format `{command name}={key combination}`

* Keybinds can be combined with any combination of Shift, Control, or Alt, e.g., `Shift+X`, `Control+Y`, `Shift+Alt+Z`, `Shift+Control+Alt+A`

### Local Configuration

Create a file named `localsettings` in a directory to create settings and custom commands for only that workspace

Should contain the following sections:

* Settings
  * debug_command - Command that executes in the debugger
  * source_control - Source control for the directory, defaults to git
  * excluded_directorie - Directories that should be excluded from searches
  * excluded_extensions - Extensions that should be excluded from searches
  * perforce_client_name - Optional p4 config for the full workspace name
  * perforce_client_suffix - Optional p4 config for the suffix of the workspace name with the name of the computer as the prefix

* Commands
  * Formatted as `{key combination}={command}`

## License

[GPL3](COPYING)
