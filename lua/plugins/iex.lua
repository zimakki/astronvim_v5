return {
  "jesseleite/iex.nvim",
  ft = { "elixir" },
  opts = {},
  config = function(_, opts)
    local iex = require("iex")

    -- Override run BEFORE setup so the BufWritePost autocmd captures
    -- our version. The plugin's default uses `mix run` + Code.eval_file
    -- which doesn't have IEx helpers (h/1, i/1, etc.). This launches a
    -- real `iex -S mix` session that auto-loads .iex.exs natively.
    iex.run = function()
      local current_win = vim.api.nvim_get_current_win()

      local existing_win = nil
      local existing_buf = nil
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(buf)
        if name == "iex:///output" then
          existing_win = win
          existing_buf = buf
          break
        end
      end

      if existing_win and existing_buf and vim.api.nvim_win_is_valid(existing_win) then
        vim.api.nvim_set_current_win(existing_win)
        vim.api.nvim_buf_set_name(existing_buf, "")
        vim.cmd.enew()
        vim.api.nvim_buf_delete(existing_buf, { force = true })
      else
        vim.cmd.vsplit()
      end

      vim.cmd.terminal("iex -S mix")
      vim.api.nvim_buf_set_name(0, "iex:///output")
      vim.wo.statusline = " iex:///output "

      vim.api.nvim_set_current_win(current_win)
      vim.cmd.stopinsert()
    end

    iex.setup(opts)
  end,
  keys = {
    { "<Leader>mi", "<cmd>IEx<cr>", desc = "Open IEx scratch file" },
    { "<Leader>mr", "<cmd>IExRun<cr>", desc = "Run IEx scratch file" },
  },
}
