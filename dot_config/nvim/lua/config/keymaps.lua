-- Keymaps are automatically loaded on the VeryLazy event
local map = vim.keymap.set

-- Save with Ctrl+S
map({ "n", "i", "v" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

-- Better escape
map("i", "jk", "<Esc>", { desc = "Escape insert mode" })

-- Center after scroll
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down and center" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up and center" })

-- Oil.nvim - open parent directory
map("n", "-", "<cmd>Oil<cr>", { desc = "Open parent directory (oil)" })
