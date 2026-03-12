-- Live markdown preview using Elixir + mdex
-- Usage: :MdexPreview to start, :MdexPreviewStop to stop
-- Theme toggle in browser: Ctrl+Shift+T

return {
  "AstroNvim/astrocore",
  opts = {
    commands = {
      MdexPreview = {
        function()
          if vim.bo.filetype ~= "markdown" then
            vim.notify("MdexPreview: not a markdown file", vim.log.levels.WARN)
            return
          end

          local file = vim.fn.expand "%:p"
          local config_dir = vim.fn.stdpath "config"
          local port = 4123

          if vim.g.mdex_preview_job then
            -- Server already running — just switch the file
            vim.fn.jobstart({ "curl", "-s", "http://localhost:" .. port .. "/switch?path=" .. file })
            vim.notify("MdexPreview: switched to " .. vim.fn.expand "%:t")
          else
            local script = config_dir .. "/scripts/mdex_preview.exs"
            local css_dir = config_dir .. "/css"
            local theme = vim.g.mdex_preview_theme or "dark"

            vim.g.mdex_preview_job = vim.fn.jobstart({
              "elixir",
              script,
              file,
              "--port",
              tostring(port),
              "--theme",
              theme,
              "--css-dir",
              css_dir,
            }, {
              on_stdout = function(_, data)
                for _, line in ipairs(data) do
                  if line ~= "" then vim.notify("MdexPreview: " .. line) end
                end
              end,
              on_stderr = function(_, data)
                for _, line in ipairs(data) do
                  if line ~= "" then vim.notify("MdexPreview ERR: " .. line, vim.log.levels.ERROR) end
                end
              end,
              on_exit = function(_, code)
                vim.g.mdex_preview_job = nil
                if code ~= 0 then
                  vim.notify("MdexPreview exited with code " .. code, vim.log.levels.WARN)
                end
              end,
            })

            vim.notify("MdexPreview starting on port " .. port .. " (first run may take ~30s to compile)")
          end
        end,
        desc = "Start Elixir live markdown preview server",
      },
      MdexPreviewStop = {
        function()
          if vim.g.mdex_preview_job then
            vim.fn.jobstop(vim.g.mdex_preview_job)
            vim.g.mdex_preview_job = nil
            vim.notify "MdexPreview stopped"
          else
            vim.notify("MdexPreview: no preview running", vim.log.levels.WARN)
          end
        end,
        desc = "Stop Elixir live markdown preview server",
      },
    },
  },
}
