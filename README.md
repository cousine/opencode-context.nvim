# opencode-context.nvim

A Neovim plugin that enables seamless context sharing with running opencode sessions inside tmux or Zellij. Send your current buffer, all open buffers, visual selections, or diagnostics directly to opencode running in a pane for AI-assisted development.

## Features

- 💬 Interactive prompt input for opencode
- 🔄 Smart placeholder replacement system
- 📄 `@file` - Insert current file path (relative)
- 📁 `@buffers` - Insert all buffer file paths (relative)
- 📍 `@cursor`, `@here` - Insert cursor position info
- ✂️ `@selection`, `@range` - Insert visual selection
- 🔍 `@diagnostics` - Insert LSP diagnostics
- 🖥️ **Tmux + Zellij integration** - Send directly to opencode pane in current window/tab
- ⚡ LazyVim compatible with lazy loading

## Requirements

- Neovim >= 0.8.0
- `tmux` or `zellij` - Required for sending messages to running opencode sessions
- `opencode` running in a pane within the same tmux window or zellij tab as Neovim

## Installation

### lazy.nvim (LazyVim)

```lua
{
  "cousine/opencode-context.nvim",
  opts = {
    multiplexer = "auto",  -- "auto", "tmux", or "zellij"
    tmux_target = nil,  -- Manual override: "session:window.pane"
    zellij_target = nil,  -- Manual override: "terminal_3"
    auto_detect_pane = true,  -- Auto-detect opencode pane in current window
  },
  keys = {
    { "<leader>oc", "<cmd>OpencodeSend<cr>", desc = "Send prompt to opencode" },
    {
      "<leader>oc",
      function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
        require("opencode-context").send_prompt(true)
      end,
      mode = "v",
      desc = "Send prompt to opencode",
    },
    { "<leader>ot", "<cmd>OpencodeSwitchMode<cr>", desc = "Toggle opencode mode" },
    { "<leader>op", "<cmd>OpencodePrompt<cr>", desc = "Open opencode persistent prompt" },
  },
  cmd = { "OpencodeSend", "OpencodeSwitchMode" },
}
```

### packer.nvim

```lua
use {
  'cousine/opencode-context.nvim',
  config = function()
    require('opencode-context').setup({
      multiplexer = "auto",
      tmux_target = nil,
      zellij_target = nil,
      auto_detect_pane = true,
    })
  end
}
```

### vim-plug

```vim
Plug 'cousine/opencode-context.nvim'

" Configuration in init.vim or init.lua
lua << EOF
require('opencode-context').setup({
  multiplexer = "auto",
  tmux_target = nil,
  zellij_target = nil,
  auto_detect_pane = true,
})

-- Keymaps
vim.keymap.set("n", "<leader>oc", "<cmd>OpencodeSend<cr>", { desc = "Send prompt to opencode" })
vim.keymap.set("v", "<leader>oc", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  require("opencode-context").send_prompt(true)
end, { desc = "Send prompt to opencode" })
vim.keymap.set("n", "<leader>ot", "<cmd>OpencodeSwitchMode<cr>", { desc = "Toggle opencode mode" })
vim.keymap.set("n", "<leader>op", "<cmd>OpencodePrompt<cr>", { desc = "Open opencode persistent prompt" })
EOF
```

### dein.vim

```vim
call dein#add('cousine/opencode-context.nvim')

" Configuration
lua << EOF
require('opencode-context').setup({
  multiplexer = "auto",
  tmux_target = nil,
  zellij_target = nil,
  auto_detect_pane = true,
})
EOF
```

### Manual Installation

1. Clone the repository to your Neovim configuration directory:

   ```bash
   git clone https://github.com/cousine/opencode-context.nvim ~/.config/nvim/pack/plugins/start/opencode-context.nvim
   ```

2. Add to your `init.lua`:

   ```lua
   require("opencode-context").setup({
      multiplexer = "auto",
      tmux_target = nil,
      zellij_target = nil,
      auto_detect_pane = true,
    })
   ```

## Usage

### Commands

- `:OpencodeSend` - Open prompt input for opencode with placeholder support
- `:OpencodeSwitchMode` - Toggle opencode between planning and build mode
- `:OpencodePrompt` - Open opencode persistent prompt

### Default Keymaps

- `<leader>oc` - Open prompt input (works in normal and visual mode)
- `<leader>om` - Toggle opencode mode (planning ↔ build)

### Placeholders

Use these placeholders in your prompts to include context:

- `@file` - Includes the current file path (relative to working directory)
- `@buffers` - Includes all buffer file paths (relative to working directory)
- `@cursor` - Includes cursor position (file, line, column)
- `@here` - Alias to @cursor
- `@selection` - Includes the current visual selection content
- `@range` - Includes the current visual selection range
- `@diagnostics` - Includes LSP diagnostics for current line

### Example Prompts

- `"Fix this error: @diagnostics"`
- `"Explain this code: @selection"` (select text first, then `<leader>oc`)
- `"What does @file do?"`
- `"Add tests for @file"`
- `"Review these buffers: @buffers"`
- `"How do these files work together: @buffers"`
- `"Help me at @cursor in @file"`

### Workflow Example

1. In your multiplexer, split your layout (`tmux`: `Ctrl-b %` / `Ctrl-b "`, `zellij`: `Alt n` by default)
2. Start opencode in one pane: `opencode`
3. Open Neovim in the other pane: `nvim`
4. From Neovim, press `<leader>oc` to open the prompt input
5. Enter your prompt with placeholders: `"Fix this error: @diagnostics"`
6. **See your prompt and response directly in the opencode pane!**

## Configuration

```lua
require("opencode-context").setup({
  -- Multiplexer settings
  multiplexer = "auto",  -- "auto", "tmux", or "zellij"

  -- Tmux settings
  tmux_target = nil,  -- Manual override: "main:1.0"
  auto_detect_pane = true,  -- Auto-find opencode pane in current tmux window/zellij tab (default: true)

  -- Zellij settings
  zellij_target = nil, -- Manual override: "terminal_3"
})
```

## How It Works

The plugin integrates directly with tmux or zellij to send messages to your running opencode session:

1. **Auto-detects** running opencode pane in the current tmux window or zellij tab
2. **Sends keystrokes directly** to the opencode pane using `tmux send-keys` or `zellij action`
3. **You see the conversation** in real-time in your opencode interface
4. **No new processes** - uses your existing opencode session

### Detection Strategy

For tmux, the plugin searches for opencode panes **only in the current tmux window** using:

- Current command is `opencode`
- Pane title contains "opencode"
- Recent command history contains opencode

For zellij, the plugin searches terminal panes in the **current active tab** and matches panes by command/title containing `opencode`.

This ensures it finds the opencode instance you're actively working with, not some other session.

## Troubleshooting

### "No opencode pane found in current tmux window"

- **Same window**: Ensure opencode is running in a pane in the **same tmux window** as Neovim
- **Split window**: Use `Ctrl-b %` or `Ctrl-b "` to split and run opencode in one pane
- **Manual target**: Set `tmux_target = "session:window.pane"` in config to override detection
- **Verify opencode is running**: Check that opencode is actually running in the current window

### "No opencode pane found in current zellij tab"

- **Same tab**: Ensure opencode is running in a pane in the **same zellij tab** as Neovim
- **Manual target**: Set `zellij_target = "terminal_3"` in config to override detection
- **Verify opencode is running**: Check pane command/title includes opencode

### "Failed to send to opencode pane"

- **Permissions**: Check tmux pane permissions
- **Target exists**: Verify the tmux target pane exists
- **Tmux session**: Ensure you're in the same tmux session or specify full target

### Debug Tips

```bash
# Check if opencode pane is detected in current window
tmux list-panes -F '#{session_name}:#{window_index}.#{pane_index}' -f '#{==:#{pane_current_command},opencode}'

# Test manual tmux send
tmux send-keys -t session:window.pane "test message" Enter

# List all panes in current window
tmux list-panes -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'

# Check zellij panes in current session
zellij action list-panes --json

# Check current zellij tab info
zellij action current-tab-info --json

# Test manual zellij send
zellij action write-chars --pane-id terminal_3 "test message"
zellij action send-keys --pane-id terminal_3 Enter
```

## Contributing

Feel free to submit issues and pull requests to improve the plugin.

## License

MIT License
