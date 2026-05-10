local context = require("opencode-context")

local M = setmetatable({}, {
  __index = context,
})

-- Backward-compatible aliases
M.toggle = function()
  return context.toggle_mode()
end

M.send = function()
  return context.send_prompt()
end

return M
