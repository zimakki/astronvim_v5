return {
  {
    -- tailwind-tools: keep conceal/fold only. Disable its LSP override because it
    -- sets the server up through the deprecated `require('lspconfig')` framework
    -- that AstroNvim v6 removed (caused "attempt to call field 'setup'").
    "luckasRanarison/tailwind-tools.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      conceal = {
        enabled = true,
      },
      server = {
        override = false,
      },
    },
  },
  {
    -- Custom tailwindcss language server settings, migrated from the removed
    -- lspconfig framework to the v6 `vim.lsp.config` API via AstroLSP.
    "AstroNvim/astrolsp",
    ---@type AstroLSPOpts
    opts = {
      config = {
        tailwindcss = {
          -- tailwind-tools calls `client.request(...)` in dot form (lsp.lua:212), which
          -- Neovim 0.12 deprecates and 0.13 removes. Upstream is stale (last commit
          -- 2025-05-23), so swap the instance wrapper Neovim installs for an equivalent
          -- that dispatches both call forms without warning. Remove once upstream
          -- switches to `client:request`.
          on_init = function(client)
            local Client = getmetatable(client)
            local request = Client and Client.request
            if not request then return end
            client.request = function(...)
              if getmetatable((select(1, ...))) == Client then return request(...) end
              return request(client, ...)
            end
          end,
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
          -- New `vim.lsp.config` root_dir signature: (bufnr, on_dir)
          root_dir = function(bufnr, on_dir)
            local fname = vim.api.nvim_buf_get_name(bufnr)

            -- Find the project root based on .git or package.json
            local root = vim.fs.root(fname, { ".git", "package.json" })

            if root then
              -- Ensure the Tailwind config exists in the wildflower/assets folder
              local tailwind_config_path = root .. "/wildflower/assets/tailwind.config.js"
              if vim.fn.filereadable(tailwind_config_path) == 1 then
                return on_dir(root) -- Return the project root (not the assets directory)
              end
            end

            return on_dir(vim.fn.getcwd())
          end,
        },
      },
    },
  },
}
