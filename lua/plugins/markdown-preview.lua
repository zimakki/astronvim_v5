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
      vim.g.mkdp_theme = "dark"
      vim.g.mkdp_markdown_css = vim.fn.expand "~/.config/nvim/css/markdown-wide.css"
    end,
  },
}
