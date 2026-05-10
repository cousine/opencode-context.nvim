local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":h:h")

vim.opt.runtimepath:prepend(root)

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function run(cmd)
  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    error(string.format("Command failed: %s\n%s", cmd, output))
  end
  return output
end

local function command_help(cmd)
  return vim.fn.system(cmd .. " --help 2>/dev/null") or ""
end

local function supports_dump_screen_pane_id()
  return command_help("zellij action dump-screen"):find("--pane%-id") ~= nil
end

local function supports_close_pane_pane_id()
  return command_help("zellij action close-pane"):find("--pane%-id") ~= nil
end

local function wait_for_file(path, timeout_ms)
  local deadline = vim.loop.hrtime() + (timeout_ms * 1000000)
  while vim.loop.hrtime() < deadline do
    if vim.fn.filereadable(path) == 1 then
      return true
    end
    vim.wait(50)
  end
  return false
end

local function read_first_line(path)
  local lines = vim.fn.readfile(path)
  if #lines == 0 then
    return nil
  end
  return trim(lines[1])
end

if not vim.env.ZELLIJ or vim.env.ZELLIJ == "" then
  error("zellij_nomock.lua must be executed inside a zellij session")
end

local capture_pane_id = nil
local capture_id_file = string.format("/tmp/opencode-context-zellij-pane-id-%d.txt", vim.fn.getpid())
local dump_file = string.format("/tmp/opencode-context-zellij-dump-%d.txt", vim.fn.getpid())
local ok, err = pcall(function()
  pcall(vim.fn.delete, capture_id_file)
  pcall(vim.fn.delete, dump_file)

  local pane_name = string.format("opencode-context-test-%d", vim.loop.hrtime())
  local inner_cmd = string.format("printf '%%s\n' \"$ZELLIJ_PANE_ID\" > %s; cat", vim.fn.shellescape(capture_id_file))
  local create_cmd = string.format(
    "zellij action new-pane --direction right --name %s -- sh -lc %s",
    vim.fn.shellescape(pane_name),
    vim.fn.shellescape(inner_cmd)
  )
  run(create_cmd)

  -- Older zellij versions do not support --pane-id targeting for write/send-keys.
  -- In that case, input goes to the focused pane, so move focus to the capture pane.
  pcall(run, "zellij action move-focus right")

  assert(wait_for_file(capture_id_file, 3000), "failed to create capture pane")
  capture_pane_id = read_first_line(capture_id_file)
  assert(capture_pane_id and capture_pane_id ~= "", "failed to read capture pane id")

  package.loaded["opencode-context"] = nil
  local opencode_context = require("opencode-context")

  opencode_context.setup({
    multiplexer = "zellij",
    zellij_target = capture_pane_id,
    auto_detect_pane = false,
  })

  local prompt_payload = "zellij-real-test-payload"
  local original_input = vim.ui.input

  vim.ui.input = function(_, on_confirm)
    on_confirm(prompt_payload)
  end

  local send_ok, send_err = pcall(function()
    opencode_context.send_prompt()
  end)

  vim.ui.input = original_input

  assert(send_ok, send_err)
  assert(opencode_context.toggle_mode() == true, "expected toggle_mode to succeed")

  vim.wait(300)

  pcall(run, "zellij action move-focus right")

  if supports_dump_screen_pane_id() then
    run(string.format("zellij action dump-screen --pane-id %s --full %s", vim.fn.shellescape(capture_pane_id), vim.fn.shellescape(dump_file)))
  else
    run(string.format("zellij action dump-screen --full %s", vim.fn.shellescape(dump_file)))
  end

  local lines = vim.fn.readfile(dump_file)
  local screen_dump = table.concat(lines, "\n")

  assert(screen_dump:find(prompt_payload, 1, true), "sent prompt not found in capture pane dump")
end)

if capture_pane_id then
  if supports_close_pane_pane_id() then
    vim.fn.system(string.format("zellij action close-pane --pane-id %s", vim.fn.shellescape(capture_pane_id)))
  else
    pcall(run, "zellij action move-focus right")
    vim.fn.system("zellij action close-pane")
  end
end

pcall(vim.fn.delete, capture_id_file)
pcall(vim.fn.delete, dump_file)

if not ok then
  error(err)
end

print("zellij no-mock integration test passed")
