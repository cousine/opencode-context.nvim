local M = {}
local ui = require("opencode-context.ui")

M.config = {
	-- Multiplexer settings
	multiplexer = "auto", -- "auto", "tmux", or "zellij"

	-- Tmux settings
	tmux_target = nil, -- Manual override: "session:window.pane"
	auto_detect_pane = true, -- Auto-detect opencode pane in current window

	-- Zellij settings
	zellij_target = nil, -- Manual override: "terminal_3"
}

local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function decode_json(value)
	if not value or value == "" then
		return nil
	end

	local ok, decoded = pcall(vim.fn.json_decode, value)
	if not ok then
		return nil
	end

	return decoded
end

local function run_system_command(cmd)
	local output = vim.fn.system(cmd)
	if vim.v.shell_error ~= 0 then
		return nil
	end

	return output
end

local function zellij_supports_send_keys()
	if M._zellij_supports_send_keys ~= nil then
		return M._zellij_supports_send_keys
	end

	M._zellij_supports_send_keys = run_system_command("zellij action send-keys --help 2>/dev/null") ~= nil
	return M._zellij_supports_send_keys
end

local function zellij_supports_tab_info()
	if M._zellij_supports_tab_info ~= nil then
		return M._zellij_supports_tab_info
	end

	M._zellij_supports_tab_info = run_system_command("zellij action current-tab-info --help 2>/dev/null") ~= nil
	return M._zellij_supports_tab_info
end

local function get_current_file_path()
	local bufnr = vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(bufnr)
	-- Convert to relative path from cwd
	local relative_path = vim.fn.fnamemodify(filename, ":~:.")
	return relative_path
end

local function get_buffers_paths()
	local buffers = vim.api.nvim_list_bufs()
	local file_paths = {}

	for _, bufnr in ipairs(buffers) do
		if vim.bo[bufnr].buflisted then
			local filename = vim.api.nvim_buf_get_name(bufnr)
			if filename and filename ~= "" then
				-- Convert to relative path from cwd
				local relative_path = vim.fn.fnamemodify(filename, ":~:.")
				if relative_path and relative_path ~= "" then
					table.insert(file_paths, relative_path)
				end
			end
		end
	end

	if #file_paths == 0 then
		return "No buffers"
	end

	return table.concat(file_paths, ", ")
end

-- returns the buffer, relative file path and cursor
local function get_cursor()
	local function is_floating(winid)
		local config = vim.api.nvim_win_get_config(winid)
		return config.relative ~= ""
	end

	local current_win = vim.api.nvim_get_current_win()
	local target_win = current_win

	if is_floating(current_win) then
		local prev_winnr = vim.fn.winnr("#")
		local prev_winid = vim.fn.win_getid(prev_winnr)

		if prev_winid ~= 0 and vim.api.nvim_win_is_valid(prev_winid) then
			target_win = prev_winid
		end
	end

	local bufnr = vim.api.nvim_win_get_buf(target_win)
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local relative_path = vim.fn.fnamemodify(filename, ":~:.")
	local cursor = vim.api.nvim_win_get_cursor(target_win)
	return bufnr, relative_path, cursor
end

local function get_cursor_info()
	local _, relative_path, cursor = get_cursor()
	local line_num = cursor[1]
	local col_num = cursor[2] + 1

	return string.format("%s, Line: %d, Column: %d", relative_path, line_num, col_num)
end

local function get_visual_selection()
	local bufnr = vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local relative_path = vim.fn.fnamemodify(filename, ":~:.")

	local start_pos, end_pos

	-- Check if we're currently in visual mode
	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" or mode == "\22" then -- \22 is visual block mode
		-- In visual mode, use current selection
		start_pos = vim.fn.getpos("v")
		end_pos = vim.fn.getpos(".")

		-- Ensure start comes before end
		if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
			start_pos, end_pos = end_pos, start_pos
		end
	else
		-- Not in visual mode, use marks from last visual selection
		start_pos = vim.fn.getpos("'<")
		end_pos = vim.fn.getpos("'>")
	end

	local start_line = start_pos[2] - 1
	local end_line = end_pos[2]
	local start_col = start_pos[3] - 1
	local end_col = end_pos[3]

	local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)

	if #lines == 1 then
		lines[1] = string.sub(lines[1], start_col + 1, end_col)
	elseif #lines > 1 then
		lines[1] = string.sub(lines[1], start_col + 1)
		lines[#lines] = string.sub(lines[#lines], 1, end_col)
	end

	local selection = table.concat(lines, "\n")

	return relative_path, start_line, end_line, selection
end

-- returns the file, range and contents of the visual selection
local function get_selection()
	local relative_path, start_line, end_line, selection = get_visual_selection()

	return string.format("%s (lines %d-%d) - `%s`", relative_path, start_line + 1, end_line, selection)
end

-- returns the file and range of the visual selection
local function get_visual_range()
	local relative_path, start_line, end_line, _ = get_visual_selection()

	return string.format("%s (lines %d-%d)", relative_path, start_line + 1, end_line)
end

local function get_diagnostics()
	local bufnr, relative_path, cursor = get_cursor()
	local current_line = cursor[1] - 1 -- Convert to 0-based indexing

	-- Get diagnostics for current line only
	local diagnostics = vim.diagnostic.get(bufnr, { lnum = current_line })

	if #diagnostics == 0 then
		return ""
	end

	local content_parts = {}

	-- Add file context at the beginning
	table.insert(content_parts, string.format("File: %s", relative_path))

	for _, diagnostic in ipairs(diagnostics) do
		local severity = vim.diagnostic.severity[diagnostic.severity]
		local line = diagnostic.lnum + 1
		local col = diagnostic.col + 1

		local message = string.format("[%s] Line %d, Col %d: %s", severity, line, col, diagnostic.message)

		if diagnostic.source then
			message = message .. string.format(" (%s)", diagnostic.source)
		end

		table.insert(content_parts, message)
	end

	return table.concat(content_parts, "\n")
end

local function replace_placeholders(prompt)
	local replacements = {
		["@buffers"] = get_buffers_paths, -- Process @buffers FIRST
		["@file"] = get_current_file_path, -- Then @file
		["@selection"] = get_selection,
		["@range"] = get_visual_range,
		["@diagnostics"] = get_diagnostics,
		["@here"] = get_cursor_info,
		["@cursor"] = get_cursor_info,
	}

	for placeholder, func in pairs(replacements) do
		if prompt:find(placeholder, 1, true) then
			local replacement = func()
			prompt = prompt:gsub(placeholder:gsub("[@]", "%%@"), replacement)
		end
	end

	return prompt
end

local function get_active_multiplexer()
	if M.config.multiplexer == "tmux" or M.config.multiplexer == "zellij" then
		return M.config.multiplexer
	end

	if M.config.tmux_target then
		return "tmux"
	end

	if M.config.zellij_target then
		return "zellij"
	end

	if vim.env.TMUX and vim.env.TMUX ~= "" then
		return "tmux"
	end

	if vim.env.ZELLIJ and vim.env.ZELLIJ ~= "" then
		return "zellij"
	end

	return nil
end

local function find_opencode_tmux_pane()
	if M.config.tmux_target then
		return M.config.tmux_target
	end

	if not M.config.auto_detect_pane then
		return nil
	end

	local current_session_cmd = "tmux display-message -p '#{session_name}'"
	local current_window_cmd = "tmux display-message -p '#{window_index}'"

	local session_handle = io.popen(current_session_cmd .. " 2>/dev/null")
	local window_handle = io.popen(current_window_cmd .. " 2>/dev/null")

	if not session_handle or not window_handle then
		return nil
	end

	local current_session = trim(session_handle:read("*a"))
	local current_window = trim(window_handle:read("*a"))
	session_handle:close()
	window_handle:close()

	if current_session == "" or current_window == "" then
		return nil
	end

	local strategies = {
		string.format(
			"tmux list-panes -t %s:%s -F '#{session_name}:#{window_index}.#{pane_index}' -f '#{==:#{pane_current_command},opencode}'",
			current_session,
			current_window
		),
		string.format(
			"tmux list-panes -t %s:%s -F '#{session_name}:#{window_index}.#{pane_index}' -f '#{m:*opencode*,#{pane_title}}'",
			current_session,
			current_window
		),
		string.format(
			"tmux list-panes -t %s:%s -F '#{session_name}:#{window_index}.#{pane_index} #{pane_start_command}' | grep opencode | head -1 | cut -d' ' -f1",
			current_session,
			current_window
		),
	}

	for _, cmd in ipairs(strategies) do
		local handle = io.popen(cmd .. " 2>/dev/null")
		if handle then
			local result = trim(handle:read("*a"))
			handle:close()
			if result ~= "" then
				return result
			end
		end
	end

	return nil
end

local function find_opencode_zellij_pane()
	if M.config.zellij_target then
		return M.config.zellij_target
	end

	if not M.config.auto_detect_pane then
		return nil
	end

	if not zellij_supports_tab_info() then
		return vim.env.ZELLIJ_PANE_ID
	end

	local current_tab_info = run_system_command("zellij action current-tab-info --json 2>/dev/null")
	if not current_tab_info then
		return nil
	end

	local current_tab = decode_json(current_tab_info)
	if not current_tab or current_tab.tab_id == nil then
		return nil
	end

	local panes_info = run_system_command("zellij action list-panes --json 2>/dev/null")
	if not panes_info then
		return nil
	end

	local panes = decode_json(panes_info)
	if type(panes) ~= "table" then
		return nil
	end

  -- First look for an exact pane titled opencode
	for _, pane in ipairs(panes) do
		if pane.is_plugin == false and pane.tab_id == current_tab.tab_id then
			local title = (pane.title or ""):lower()
			local command = (pane.pane_command or pane["pane-command"] or ""):lower()
			if title == "opencode" or command == "opencode" then
				return string.format("terminal_%d", pane.id)
			end
		end
	end

  -- then do a substring match
	for _, pane in ipairs(panes) do
		if pane.is_plugin == false and pane.tab_id == current_tab.tab_id then
			local title = (pane.title or ""):lower()
			local command = (pane.pane_command or pane["pane-command"] or ""):lower()
			if string.find(command, "opencode") ~= nil or string.find(title, "opencode") ~= nil then
				return string.format("terminal_%d", pane.id)
			end
		end
	end

	return nil
end

local function find_opencode_target(multiplexer)
	if multiplexer == "tmux" then
		return find_opencode_tmux_pane()
	end

	if multiplexer == "zellij" then
		return find_opencode_zellij_pane()
	end

	return nil
end

local function notify_missing_multiplexer()
	vim.notify(
		"No supported terminal multiplexer detected. Start Neovim in tmux or zellij, or configure multiplexer/target explicitly.",
		vim.log.levels.ERROR
	)
end

local function notify_missing_target(multiplexer)
	if multiplexer == "tmux" then
		vim.notify(
			"No opencode pane found in current tmux window. Make sure opencode is running in this tmux window.",
			vim.log.levels.ERROR
		)
		return
	end

	vim.notify(
		"No opencode pane found in current zellij tab. Make sure opencode is running in this zellij tab.",
		vim.log.levels.ERROR
	)
end

local function resolve_opencode_target()
	local multiplexer = get_active_multiplexer()
	if not multiplexer then
		notify_missing_multiplexer()
		return nil, nil
	end

	local target = find_opencode_target(multiplexer)
	if not target then
		notify_missing_target(multiplexer)
		return multiplexer, nil
	end

	return multiplexer, target
end

local function send_to_opencode(message)
	local multiplexer, target = resolve_opencode_target()
	if not multiplexer or not target then
		return false
	end

	local success = false

	if multiplexer == "tmux" then
		local write_cmd = string.format(
			"tmux send-keys -t %s %s",
			vim.fn.shellescape(target),
			vim.fn.shellescape(message)
		)
		local enter_cmd = string.format("tmux send-keys -t %s C-m", vim.fn.shellescape(target))

		if run_system_command(write_cmd) and run_system_command(enter_cmd) then
			success = true
		end
	else
		local write_cmd
		local enter_cmd

		if zellij_supports_send_keys() then
			write_cmd = string.format(
				"zellij action write-chars --pane-id %s %s",
				vim.fn.shellescape(target),
				vim.fn.shellescape(message)
			)
			enter_cmd = string.format(
				"zellij action send-keys --pane-id %s Enter",
				vim.fn.shellescape(target)
			)
		else
			write_cmd = string.format("zellij action write-chars %s", vim.fn.shellescape(message))
			enter_cmd = "zellij action write 13"
		end

		if run_system_command(write_cmd) and run_system_command(enter_cmd) then
			success = true
		end
	end

	if success then
		vim.notify(string.format("Sent prompt to opencode pane (%s via %s)", target, multiplexer), vim.log.levels.INFO)
		return true
	end

	vim.notify(string.format("Failed to send prompt via %s", multiplexer), vim.log.levels.ERROR)
	return false
end

function M.send_prompt(use_selection_default)
	-- Visual mappings can exit to Normal mode before opening the prompt,
	-- so allow callers to explicitly preserve the @selection default.
	local mode = vim.fn.mode()
	local default_text = ""
	if use_selection_default or mode == "v" or mode == "V" or mode == "\22" then -- \22 is visual block mode
		default_text = "@selection "
	end

	vim.ui.input({
		prompt = "Enter prompt for opencode (use @file, @buffers, @cursor, @selection, @diagnostics): ",
		default = default_text,
	}, function(input)
		if not input or input == "" then
			return
		end

		local processed_prompt = replace_placeholders(input)
		send_to_opencode(processed_prompt)
	end)
end

function M.toggle_mode()
	local multiplexer, target = resolve_opencode_target()
	if not multiplexer or not target then
		return false
	end

	local cmd
	if multiplexer == "tmux" then
		cmd = string.format("tmux send-keys -t %s Tab", vim.fn.shellescape(target))
	else
		if zellij_supports_send_keys() then
			cmd = string.format("zellij action send-keys --pane-id %s Tab", vim.fn.shellescape(target))
		else
			cmd = "zellij action write 9"
		end
	end

	if run_system_command(cmd) then
		vim.notify(string.format("Toggled opencode mode (%s via %s)", target, multiplexer), vim.log.levels.INFO)
		return true
	end

	vim.notify(string.format("Failed to toggle opencode mode via %s", multiplexer), vim.log.levels.ERROR)
	return false
end

-- Create a callback that processes placeholders and sends to opencode
local function create_send_callback()
	return function(prompt)
		local processed_prompt = replace_placeholders(prompt)
		return send_to_opencode(processed_prompt)
	end
end

function M.show_persistent_prompt()
	ui.show_persistent_prompt(create_send_callback())
end

function M.hide_persistent_prompt()
	ui.hide_persistent_prompt()
end

function M.toggle_persistent_prompt()
	ui.toggle_persistent_prompt(create_send_callback())
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	M._zellij_supports_send_keys = nil
	M._zellij_supports_tab_info = nil
end

return M
