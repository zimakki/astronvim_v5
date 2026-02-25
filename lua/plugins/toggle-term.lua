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

        -- Use functions so dimensions are recalculated on every resize
        -- (toggleterm's _resolve_size handles type(size) == "function")
        width = function() return vim.o.columns end,
        height = function() return vim.o.lines end,
      })

      -- Return the modified options table for lazy.nvim to use
      return opts
    end,
  },
}
