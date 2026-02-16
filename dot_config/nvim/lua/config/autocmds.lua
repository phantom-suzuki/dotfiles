-- Autocmds are automatically loaded on the VeryLazy event
local autocmd = vim.api.nvim_create_autocmd

-- Go: use tabs instead of spaces
autocmd("FileType", {
  pattern = { "go", "gomod", "gowork", "gotmpl" },
  callback = function()
    vim.opt_local.expandtab = false
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
  end,
})

-- Terraform: set filetype for .tf files
autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.tf", "*.tfvars" },
  callback = function()
    vim.bo.filetype = "terraform"
  end,
})
