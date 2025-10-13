local config = require("opencode-context.config")

local M = {}

-- UI state
local prompt_win = nil
local prompt_buf = nil

local safe_size = function(size, min, max)
	local safe_size = size

	-- If less or equal to zero, return minimum allowed
	-- size.
	if safe_size <= 0 then
		return min
	end

	-- If size is between 0 and 1, assume is a percentage of
	-- max allowed size.
	if safe_size < 1 then
		safe_size = math.floor(max * safe_size)
	end

	return safe_size
end

local function safe_height(height)
	local min_height = 1
	local max_height = math.floor(0.9 * vim.o.lines)
	return safe_size(height, min_height, max_height)
end

local function safe_width(width)
	local min_width = math.floor(0.1 * vim.o.columns)
	local max_width = math.floor(0.9 * vim.o.columns)
	return safe_size(width, min_width, max_width)
end

local function create_prompt_buffer()
	if prompt_buf and vim.api.nvim_buf_is_valid(prompt_buf) then
		return prompt_buf
	end

	prompt_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[prompt_buf].buftype = "nofile"
	vim.bo[prompt_buf].swapfile = false
	vim.bo[prompt_buf].filetype = "opencode-prompt"

	-- Set initial empty content
	vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { "" })

	return prompt_buf
end

local function setup_prompt_keymaps(bufnr, send_callback, type)
	local opts = { buffer = bufnr, silent = true }

	-- Enter to send prompt
	vim.keymap.set("i", "<CR>", function()
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local prompt = table.concat(lines, "\n")

		-- Skip if empty
		if not prompt:match("%S") then
			return
		end

		if send_callback(prompt) then
			-- Clear the buffer after successful send
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
			-- Only set cursor if window is still valid
			if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
				vim.api.nvim_win_set_cursor(prompt_win, { 1, 0 })
			end
		end

		if type == "input" then
			M.hide_prompt()
		end
	end, opts)

	-- Escape to return to normal mode
	vim.keymap.set("i", "<Esc>", function()
		vim.cmd("stopinsert")
		if type == "input" then
			if prompt_buf and vim.api.nvim_buf_is_valid(prompt_buf) then
				-- Clear prompt buffer
				vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { "" })
			end
			M.hide_prompt()
		end
	end, opts)

	-- Close prompt window with 'q' in normal mode
	vim.keymap.set("n", "q", function()
		M.hide_prompt()
	end, opts)
end

function M.show_prompt(send_callback, type)
	if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
		vim.api.nvim_set_current_win(prompt_win)
		vim.cmd("startinsert")
		return
	end

	local bufnr = create_prompt_buffer()

	local relative = "cursor"
	local width = safe_width(config.win.input.width)
	local height = safe_height(config.win.input.height)
	local row = 0
	local column = 0
	local border = "rounded"

	if type == "persistent" then
		relative = "editor"
		width = safe_width(vim.o.columns)
		height = safe_height(config.win.persistent.height)
		row = vim.o.lines - height - 3 -- Position above statusline/powerline
		column = 2
		border = "solid"
	end

	-- Create floating window
	prompt_win = vim.api.nvim_open_win(bufnr, true, {
		relative = relative,
		width = width,
		height = height,
		row = row,
		col = column,
		style = "minimal",
		border = border,
		title = config.win.icon .. " OpenCode - use @file, @buffers, @cursor, @selection, @diagnostics, @here",
		title_pos = "left",
	})

	-- Set window options
	vim.wo[prompt_win].wrap = true
	vim.wo[prompt_win].linebreak = true

	-- Setup keymaps for this buffer
	setup_prompt_keymaps(bufnr, send_callback, type)

	-- Start in insert mode
	vim.cmd("startinsert")

	-- Auto-hide on focus lost
	vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
		buffer = bufnr,
		callback = function()
			vim.defer_fn(function()
				if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
					local current_win = vim.api.nvim_get_current_win()
					if current_win ~= prompt_win then
						M.hide_prompt()
					end
				end
			end, 100)
		end,
		once = false,
	})
end

function M.hide_prompt()
	if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
		vim.api.nvim_win_close(prompt_win, false)
		prompt_win = nil
	end
end

function M.toggle_prompt(send_callback, type)
	if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
		M.hide_prompt()
	else
		M.show_prompt(send_callback, type)
	end
end

function M.is_prompt_visible()
	return prompt_win and vim.api.nvim_win_is_valid(prompt_win)
end

function M.add_text_at_cursor(text)
	if not prompt_buf or not vim.api.nvim_buf_is_valid(prompt_buf) then
		return false
	end

	if not prompt_win or not vim.api.nvim_win_is_valid(prompt_win) then
		return false
	end

	if not text or text == "" then
		return false
	end

	-- Clear prompt buffer
	vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { "" })

	-- Current cursor position
	local row = 0
	local col = 0

	-- Get current buffer content
	local lines = vim.api.nvim_buf_get_lines(prompt_buf, 0, -1, false)

	-- Split the text to insert into lines
	local text_lines = vim.split(text, "\n", { plain = true })

	-- Handle single line insertion
	if #text_lines == 1 then
		local current_line = lines[row + 1] or ""
		local before = current_line:sub(1, col)
		local after = current_line:sub(col + 1)
		lines[row + 1] = before .. text .. after

		-- Update buffer
		vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, lines)

		-- Move cursor to end of inserted text
		vim.api.nvim_win_set_cursor(prompt_win, { row + 1, col + #text })
	else
		-- Handle multi-line insertion
		local current_line = lines[row + 1] or ""
		local before = current_line:sub(1, col)
		local after = current_line:sub(col + 1)

		-- Create newlines array
		local new_lines = {}

		-- Add lines before insertion point
		for i = 1, row do
			new_lines[i] = lines[i]
		end

		-- Add first line of insertion (with before text)
		new_lines[row + 1] = before .. text_lines[1]

		-- Add middle lines of insertion
		for i = 2, #text_lines - 1 do
			new_lines[row + i] = text_lines[i]
		end
		-- Add last line of insertion (with after text)
		local last_text_line = text_lines[#text_lines]
		new_lines[row + #text_lines] = last_text_line .. after

		-- Add remaining lines after insertion point
		for i = row + 2, #lines do
			new_lines[row + #text_lines + (i - row - 1)] = lines[i]
		end

		-- Update buffer
		vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, new_lines)

		-- Move cursor to end of inserted text
		vim.api.nvim_win_set_cursor(prompt_win, { row + #text_lines, #last_text_line })
	end

	return true
end

return M
