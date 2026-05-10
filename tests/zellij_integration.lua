local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":h:h")

vim.opt.runtimepath:prepend(root)

local function has_command(commands, needle)
  for _, command in ipairs(commands) do
    if command:find(needle, 1, true) then
      return true
    end
  end
  return false
end

local original_system = vim.fn.system
local original_input = vim.ui.input
local original_notify = vim.notify
local original_zellij = vim.env.ZELLIJ
local original_tmux = vim.env.TMUX

local observed_commands = {}
local notifications = {}

local function teardown()
  vim.fn.system = original_system
  vim.ui.input = original_input
  vim.notify = original_notify
  vim.env.ZELLIJ = original_zellij
  vim.env.TMUX = original_tmux
end

local ok, err = pcall(function()
  original_system("true")

  vim.env.ZELLIJ = "0"
  vim.env.TMUX = ""

  vim.notify = function(message, level)
    table.insert(notifications, { message = message, level = level })
  end

  vim.fn.system = function(command)
    table.insert(observed_commands, command)

    if command:find("zellij action current-tab-info --json", 1, true) then
      return '{"tab_id":1}'
    end

    if command:find("zellij action list-panes --json", 1, true) then
      return '[{"id":3,"is_plugin":false,"tab_id":1,"pane_command":"opencode","title":"opencode"}]'
    end

    return ""
  end

  vim.ui.input = function(_, on_confirm)
    on_confirm("hello from zellij test")
  end

  package.loaded["opencode-context"] = nil
  local opencode_context = require("opencode-context")
  opencode_context.setup({
    multiplexer = "auto",
    auto_detect_pane = true,
  })

  local toggle_ok = opencode_context.toggle_mode()
  assert(toggle_ok == true, "expected toggle_mode() to succeed with zellij")

  opencode_context.send_prompt()

  assert(has_command(observed_commands, "zellij action current-tab-info --json"), "missing current-tab-info call")
  assert(has_command(observed_commands, "zellij action list-panes --json"), "missing list-panes call")
  assert(has_command(observed_commands, "zellij action send-keys --pane-id 'terminal_3' Tab"), "missing zellij Tab send")
  assert(has_command(observed_commands, "zellij action write-chars --pane-id 'terminal_3'"), "missing zellij write-chars")
  assert(has_command(observed_commands, "hello from zellij test"), "missing prompt payload in write-chars")
  assert(has_command(observed_commands, "zellij action send-keys --pane-id 'terminal_3' Enter"), "missing zellij Enter send")

  local saw_success_notification = false
  for _, item in ipairs(notifications) do
    if item.message:find("via zellij", 1, true) then
      saw_success_notification = true
      break
    end
  end

  assert(saw_success_notification, "expected success notification mentioning zellij")
end)

teardown()

if not ok then
  error(err)
end

print("zellij integration test passed")
