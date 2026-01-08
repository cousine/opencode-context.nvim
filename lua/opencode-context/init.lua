local M = {}
local ui = require("opencode-context.ui")
local config = require("opencode-context.config")

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
		local win_cfg = vim.api.nvim_win_get_config(winid)
		return win_cfg.relative ~= ""
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

local function find_opencode_pane()
	-- If manual target is set, use it
	if config.tmux_target then
		return config.tmux_target
	end

	if not config.auto_detect_pane then
		return nil
	end

	-- Get current session and window
	local current_session_cmd = "tmux display-message -p '#{session_name}'"
	local current_window_cmd = "tmux display-message -p '#{window_index}'"

	local session_handle = io.popen(current_session_cmd .. " 2>/dev/null")
	local window_handle = io.popen(current_window_cmd .. " 2>/dev/null")

	if not session_handle or not window_handle then
		return nil
	end

	local current_session = session_handle:read("*a"):gsub("\n", "")
	local current_window = window_handle:read("*a"):gsub("\n", "")
	session_handle:close()
	window_handle:close()

	if not current_session or current_session == "" or not current_window or current_window == "" then
		return nil
	end

	-- Search for opencode pane in current window only
	local strategies = {
		-- Current command is opencode in current window
		string.format(
			"tmux list-panes -t %s:%s -F '#{session_name}:#{window_index}.#{pane_index}' -f '#{==:#{pane_current_command},opencode}'",
			current_session,
			current_window
		),

		-- Pane title contains opencode in current window
		string.format(
			"tmux list-panes -t %s:%s -F '#{session_name}:#{window_index}.#{pane_index}' -f '#{m:*opencode*,#{pane_title}}'",
			current_session,
			current_window
		),

		-- Recent command history contains opencode in current window
		string.format(
			"tmux list-panes -t %s:%s -F '#{session_name}:#{window_index}.#{pane_index} #{pane_start_command}' | grep opencode | head -1 | cut -d' ' -f1",
			current_session,
			current_window
		),
	}

	for _, cmd in ipairs(strategies) do
		local handle = io.popen(cmd .. " 2>/dev/null")
		if handle then
			local result = handle:read("*a"):gsub("\n", "")
			handle:close()
			if result and result ~= "" then
				return result
			end
		end
	end

	return nil
end

local function send_to_opencode(message)
	local pane = find_opencode_pane()
	if not pane then
		vim.notify(
			"No opencode pane found in current window. Make sure opencode is running in a pane in this tmux window.",
			vim.log.levels.ERROR
		)
		return false
	end

	-- Send message directly to the pane
	local cmd = string.format("tmux send-keys -t %s %s", pane, vim.fn.shellescape(message))
	vim.fn.system(cmd)
	vim.fn.system(string.format("tmux send-keys -t %s C-m", pane))

	if vim.v.shell_error == 0 then
		vim.notify(string.format("Sent prompt to opencode pane (%s)", pane), vim.log.levels.INFO)
		return true
	else
		vim.notify("Failed to send to opencode pane", vim.log.levels.ERROR)
		return false
	end
end

function M.send_prompt()
	-- Check if we're in visual mode and pre-populate with @selection
	local mode = vim.fn.mode()
	local default_text = ""
	if mode == "v" or mode == "V" or mode == "\22" then -- \22 is visual block mode
		default_text = "@selection "
	else
		default_text = "@cursor "
	end

	M.show_input_prompt()
	M.add_text_to_prompt(default_text)
end

function M.toggle_mode()
	local pane = find_opencode_pane()
	if not pane then
		vim.notify(
			"No opencode pane found in current window. Make sure opencode is running in a pane in this tmux window.",
			vim.log.levels.ERROR
		)
		return false
	end

	-- Send tab key to toggle between planning/build mode
	local cmd = string.format("tmux send-keys -t %s Tab", pane)
	vim.fn.system(cmd)

	if vim.v.shell_error == 0 then
		vim.notify(string.format("Toggled opencode mode (%s)", pane), vim.log.levels.INFO)
		return true
	else
		vim.notify("Failed to toggle opencode mode", vim.log.levels.ERROR)
		return false
	end
end

-- Create a callback that processes placeholders and sends to opencode
local function create_send_callback()
	return function(prompt)
		local processed_prompt = replace_placeholders(prompt)
		return send_to_opencode(processed_prompt)
	end
end

function M.show_persistent_prompt()
	ui.show_prompt(create_send_callback(), "persistent")
end

function M.hide_persistent_prompt()
	ui.hide_prompt()
end

function M.toggle_persistent_prompt()
	ui.toggle_prompt(create_send_callback(), "persistent")
end

function M.show_input_prompt()
	ui.show_prompt(create_send_callback(), "input")
end

function M.add_text_to_prompt(text)
	return ui.add_text_at_cursor(text)
end

function M.setup(opts)
	require("opencode-context.config").update(opts)
end

return M
