-- Enable snacks.nvim image doc rendering (mermaid diagrams, markdown images)
-- Uses float-only mode since Warp terminal lacks Kitty unicode placeholders

return {
  {
    "folke/snacks.nvim",
    opts = {
      image = {
        doc = {
          enabled = true,
          inline = false, -- Warp doesn't support Kitty unicode placeholders
          float = true, -- render in floating windows instead
        },
      },
    },
  },
}
