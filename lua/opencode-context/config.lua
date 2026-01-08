local default_config = {
  -- Tmux settings
	tmux_target = nil, -- Manual override: "session:window.pane"
	auto_detect_pane = true, -- Auto-detect opencode pane in current window

  -- Prompt window configuration
	win = {
		icon = " ",
		input = {
			width = 0.60,
			height = 0.30,
		},
		persistent = {
			height = 2,
		},
	},
}

local M = vim.deepcopy(default_config)

M.update = function(opts)
	local newconf = vim.tbl_deep_extend("force", default_config, opts or {})

	for k, v in pairs(newconf) do
		M[k] = v
	end
end

return M
