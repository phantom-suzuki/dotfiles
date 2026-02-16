return {
  -- oil.nvim: file explorer as a buffer
  {
    "stevearc/oil.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      default_file_explorer = true,
      view_options = {
        show_hidden = true,
      },
      float = {
        padding = 2,
        max_width = 120,
        max_height = 40,
      },
    },
  },
  -- neo-tree: keep for sidebar usage but don't replace oil as default
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      filesystem = {
        filtered_items = {
          visible = true,
          hide_dotfiles = false,
          hide_gitignored = false,
        },
      },
    },
  },
}
