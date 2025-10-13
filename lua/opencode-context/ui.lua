local config = require("opencode-context.config")

local M = {}

-- UI state
local prompt_win = nil
local prompt_buf = nil

local safe_size = function(size, min, max)
	local safe_size = size

	-- If less or equal to zero, return min allowed
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
	local max_height = math.floor(0.9 * vim.o.lines)
	return safe_size(height, 1, max_height)
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

local function setup_prompt_keymaps(bufnr, send_callback)
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
	end, opts)

	-- Escape to return to normal mode
	vim.keymap.set("i", "<Esc>", function()
		vim.cmd("stopinsert")
	end, opts)

	-- Close prompt window with 'q' in normal mode
	vim.keymap.set("n", "q", function()
		M.hide_persistent_prompt()
	end, opts)
end

function M.show_persistent_prompt(send_callback)
	if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
		vim.api.nvim_set_current_win(prompt_win)
		vim.cmd("startinsert")
		return
	end

	local bufnr = create_prompt_buffer()

	-- Get editor dimensions
	local width = vim.o.columns
	local height = safe_height(config.win.persistent.height) -- Increased to accommodate 2-line title
	local row = vim.o.lines - height - 3 -- Position above statusline/powerline

	-- Create floating window
	prompt_win = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = 2,
		style = "minimal",
		border = "solid",
		title = config.win.icon .. " OpenCode - use @file, @buffers, @cursor, @selection, @diagnostics, @here",
		title_pos = "left",
	})

	-- Set window options
	vim.wo[prompt_win].wrap = true
	vim.wo[prompt_win].linebreak = true

	-- Setup keymaps for this buffer
	setup_prompt_keymaps(bufnr, send_callback)

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
						M.hide_persistent_prompt()
					end
				end
			end, 100)
		end,
		once = false,
	})
end

function M.hide_persistent_prompt()
	if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
		vim.api.nvim_win_close(prompt_win, false)
		prompt_win = nil
	end
end

function M.toggle_persistent_prompt(send_callback)
	if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
		M.hide_persistent_prompt()
	else
		M.show_persistent_prompt(send_callback)
	end
end

function M.is_prompt_visible()
	return prompt_win and vim.api.nvim_win_is_valid(prompt_win)
end

return M
