return {
  "opencode-context.nvim",
  dev = true,
  opts = {
    -- Multiplexer settings
    multiplexer = "auto", -- "auto", "tmux", or "zellij"

    -- Tmux settings
    tmux_target = nil,  -- Manual override: "session:window.pane"
    auto_detect_pane = true,  -- Auto-detect opencode pane in current window

    -- Zellij settings
    zellij_target = nil, -- Manual override: "terminal_3"
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
    { "<leader>om", "<cmd>OpencodeSwitchMode<cr>", desc = "Toggle opencode mode" },
  },
  cmd = {
    "OpencodeSend",
    "OpencodeSwitchMode",
  },
  config = function(_, opts)
    require("opencode-context").setup(opts)
  end,
}
