-- Live markdown preview in browser with mermaid diagram support
-- Uses Prism.js (forked) for better Elixir syntax highlighting
-- Usage: :MarkdownPreview to open, :MarkdownPreviewStop to close

return {
  {
    "zimakki/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = "cd app && npm install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
      vim.g.mkdp_auto_close = 1
      vim.g.mkdp_theme = "dark" -- light, dark, system
      vim.g.mkdp_markdown_css = vim.fn.stdpath "config" .. "/css/markdown-wide.css"

      vim.api.nvim_create_user_command("MarkdownPreviewThemeToggle", function()
        local current = vim.g.mkdp_theme
        vim.g.mkdp_theme = current == "dark" and "light" or "dark"
        vim.cmd "MarkdownPreviewStop"
        vim.defer_fn(function() vim.cmd "MarkdownPreview" end, 300)
        vim.notify("Markdown theme: " .. vim.g.mkdp_theme)
      end, { desc = "Toggle markdown preview light/dark theme" })
    end,
  },
}
