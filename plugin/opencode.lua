if vim.g.loaded_opencode then
	return
end
vim.g.loaded_opencode = 1

local opencode = require("opencode-context")

local function send_visual_prompt()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
	opencode.send_prompt(true)
end

vim.api.nvim_create_user_command("OpencodeSend", function()
	opencode.send_prompt()
end, {
	desc = "Send prompt to opencode with placeholder support",
})

vim.api.nvim_create_user_command("OpencodeSwitchMode", function()
	opencode.toggle_mode()
end, {
	desc = "Toggle opencode between planning and build mode",
})

vim.api.nvim_create_user_command("OpencodePrompt", function()
	opencode.toggle_persistent_prompt()
end, {
	desc = "Toggle persistent opencode prompt window",
})

local function create_keymaps()
	vim.keymap.set("n", "<leader>oc", opencode.send_prompt, { desc = "Send prompt to opencode" })
	vim.keymap.set("v", "<leader>oc", send_visual_prompt, { desc = "Send prompt to opencode" })
	vim.keymap.set("n", "<leader>ot", opencode.toggle_mode, { desc = "Toggle opencode mode" })
	vim.keymap.set("n", "<leader>op", opencode.toggle_persistent_prompt, { desc = "Toggle persistent opencode prompt" })
end

vim.api.nvim_create_autocmd("VimEnter", {
	callback = create_keymaps,
	once = true,
})
