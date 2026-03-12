-- Live markdown preview using the standalone inkwell CLI

local function inkwell_bin()
  if vim.g.inkwell_bin and vim.fn.executable(vim.g.inkwell_bin) == 1 then return vim.g.inkwell_bin end

  local local_bin = vim.fn.expand "~/code/zimakki/inkwell/inkwell"
  if vim.fn.executable(local_bin) == 1 then return local_bin end

  if vim.fn.executable "inkwell" == 1 then return "inkwell" end
end

local function run_inkwell(args)
  local bin = inkwell_bin()

  if not bin then
    vim.notify("Inkwell: executable not found", vim.log.levels.ERROR)
    return
  end

  vim.fn.jobstart(vim.list_extend({ bin }, args), { detach = true })
end

return {
  "AstroNvim/astrocore",
  opts = {
    commands = {
      InkwellPreview = {
        function()
          if vim.bo.filetype ~= "markdown" then
            vim.notify("Inkwell: not a markdown file", vim.log.levels.WARN)
            return
          end

          run_inkwell { "preview", vim.fn.expand "%:p", "--theme", vim.g.inkwell_theme or "dark" }
        end,
        desc = "Open current markdown file in inkwell preview",
      },
      InkwellStop = {
        function() run_inkwell { "stop" } end,
        desc = "Stop the inkwell daemon",
      },
      InkwellStatus = {
        function() run_inkwell { "status" } end,
        desc = "Show inkwell daemon status",
      },
    },
  },
}
