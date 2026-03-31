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
          vertical = {
            fullscreen = true,
          },
        },
        actions = {
          toggle_layout = function(picker)
            local is_default = picker.resolved_layout.layout.box == "horizontal"
            local next_layout = is_default and "vertical" or "default"
            picker:set_layout(next_layout)
          end,
        },
        win = {
          input = {
            keys = {
              ["<C-\\>"] = { "toggle_layout", mode = { "i", "n" } },
            },
          },
        },
      },
    },
  },
}
