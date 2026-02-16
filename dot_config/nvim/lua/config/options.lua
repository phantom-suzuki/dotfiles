-- Options are automatically loaded before lazy.nvim startup
local opt = vim.opt

opt.clipboard = "unnamedplus"   -- System clipboard
opt.tabstop = 2                 -- Tab width
opt.shiftwidth = 2              -- Indent width
opt.expandtab = true            -- Use spaces
opt.relativenumber = true       -- Relative line numbers
opt.scrolloff = 8               -- Lines around cursor
opt.sidescrolloff = 8
opt.wrap = false                -- No line wrap
opt.termguicolors = true        -- True colors
opt.signcolumn = "yes"          -- Always show sign column
opt.cursorline = true           -- Highlight current line
opt.undofile = true             -- Persistent undo
opt.swapfile = false            -- No swap files
opt.updatetime = 200            -- Faster completion
opt.timeoutlen = 300            -- Faster key sequence
