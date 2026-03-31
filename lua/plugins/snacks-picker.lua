-- Make the default (centered float) picker layout fullscreen
-- This affects pickers like <leader>ff but not ivy-style pickers like <leader>fl

return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        layouts = {
          default = {
            fullscreen = true,
          },
        },
        win = {
          input = {
            keys = {
              ["<C-\\>"] = { "layout_cycle", mode = { "i", "n" } },
            },
          },
        },
      },
    },
  },
}
