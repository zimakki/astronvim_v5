return {
  {
    "akinsho/toggleterm.nvim",
    -- Use the function form of opts to safely modify existing options
    opts = function(_, opts)
      -- Safely merge settings into opts.float_opts, creating the table if needed.
      -- This sets the default border style and calculates integer dimensions
      -- for floating terminals managed by toggleterm.
      opts.float_opts = vim.tbl_deep_extend("force", opts.float_opts or {}, {
        border = "rounded", -- Specify the desired border style ("single", "double", "shadow", "none", etc.)

        -- Calculate integer width based on 100% of editor width (fraction = 1)
        -- math.floor ensures it's an integer for the nvim API
        width = math.floor(vim.o.columns * 1),

        -- Calculate integer height based on 100% of editor height (fraction = 1)
        height = math.floor(vim.o.lines * 1),
      })

      -- Return the modified options table for lazy.nvim to use
      return opts
    end,
  },
}
