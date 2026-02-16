return {
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        -- LSP servers
        "gopls",
        "typescript-language-server",
        "eslint-lsp",
        "pyright",
        "terraform-ls",
        "tflint",
        "lua-language-server",
        "json-lsp",
        "yaml-language-server",
        -- Formatters
        "goimports",
        "gofumpt",
        "prettier",
        "ruff",
        "stylua",
        -- Linters
        "eslint_d",
      },
    },
  },
}
