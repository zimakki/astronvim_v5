-- Inkwell integration for markdown buffers.
-- Users can override the CLI path with: vim.g.inkwell_cmd = "inkwell"

-- Launch Inkwell for the current buffer. This is shared by the keymap and command.
local function preview_current_markdown()
  local cmd = vim.g.inkwell_cmd or "inkwell"
  local file = vim.fn.expand "%:p"

  local job_id = vim.fn.jobstart({ cmd, "preview", file }, { detach = true })

  -- jobstart returns <= 0 when Neovim could not launch the command.
  if job_id <= 0 then
    vim.notify("Failed to start Inkwell. Is `" .. cmd .. "` installed and on your PATH?", vim.log.levels.ERROR)
  end
end

return {
  "AstroNvim/astrocore",
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "markdown",
      callback = function(args)
        -- Buffer-local command for users who prefer commands over keymaps.
        vim.api.nvim_buf_create_user_command(args.buf, "InkwellPreview", preview_current_markdown, {
          desc = "Preview the current markdown file in Inkwell",
        })

        -- Buffer-local mapping so this only exists in markdown files.
        vim.keymap.set("n", "<leader>mp", preview_current_markdown, {
          buffer = args.buf,
          desc = "Preview in Inkwell",
        })
      end,
    })
  end,
}
