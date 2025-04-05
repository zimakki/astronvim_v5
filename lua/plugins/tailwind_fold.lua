return {
  -- tailwind-tools.lua
  "luckasRanarison/tailwind-tools.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  opts = {
    conceal = {
      enabled = true,
    },
  }, -- your configuration
  config = function()
    -- Call the original plugin setup
    require("tailwind-tools").setup {}

    -- Add the root_dir function for LSP
    require("lspconfig").tailwindcss.setup {
      init_options = {
        -- Keeping userLanguages to ensure intellisense still works
        userLanguages = {
          elixir = "phoenix-heex",
          heex = "phoenix-heex",
        },
      },
      settings = {
        -- Include languages properly for TailwindCSS
        includeLanguages = {
          ["html-eex"] = "html",
          ["phoenix-heex"] = "html",
          heex = "html",
          eelixir = "html",
          elixir = "html",
        },
      },
      root_dir = function(fname)
        local lspconfig_util = require "lspconfig.util"

        -- Find the project root based on .git or package.json (or other common project markers)
        local root_pattern = lspconfig_util.root_pattern(".git", "package.json")
        local root = root_pattern(fname)

        -- If the project root is found, log and return the root
        if root then
          -- Ensure the Tailwind config exists in the wildflower/assets folder
          local tailwind_config_path = root .. "/wildflower/assets/tailwind.config.js"
          if vim.fn.filereadable(tailwind_config_path) == 1 then
            return root -- Return the project root (not the assets directory)
          end
        end

        return vim.fn.getcwd()
      end,
    }
  end,
}
