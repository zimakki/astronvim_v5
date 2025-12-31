-- Expert LSP configuration
-- The official Elixir Language Server

return {
  {
    "neovim/nvim-lspconfig",
    opts = function()
      -- Register Expert as a custom lspconfig server
      local configs = require "lspconfig.configs"
      local util = require "lspconfig.util"

      if not configs.expert then
        configs.expert = {
          default_config = {
            cmd = { vim.fn.expand "~/.local/bin/expert", "--stdio" },
            filetypes = { "elixir", "eelixir", "heex" },
            root_dir = util.root_pattern("mix.exs", ".git"),
            settings = {},
          },
        }
      end

      -- Set up Expert directly
      require("lspconfig").expert.setup {
        capabilities = require("astrolsp").config.capabilities,
        on_attach = require("astrolsp").on_attach,
      }
    end,
  },
  {
    "AstroNvim/astrocore",
    opts = {
      commands = {
        ExpertUpdate = {
          function()
            local binary_path = vim.fn.expand "~/.local/bin/expert"
            local temp_path = binary_path .. ".new"

            vim.notify("Downloading latest Expert nightly...", vim.log.levels.INFO)

            local cmd = string.format(
              "gh release download nightly --pattern 'expert_darwin_arm64' --repo elixir-lang/expert --output %s --clobber && chmod +x %s && mv %s %s",
              temp_path,
              temp_path,
              temp_path,
              binary_path
            )

            vim.fn.jobstart(cmd, {
              on_exit = function(_, exit_code)
                if exit_code == 0 then
                  vim.notify("Expert updated successfully! Restart LSP with :LspRestart", vim.log.levels.INFO)
                else
                  vim.notify("Expert update failed. Check if gh CLI is installed and authenticated.", vim.log.levels.ERROR)
                end
              end,
            })
          end,
          desc = "Update Expert LSP to latest nightly build",
        },
      },
    },
  },
}
