-- Live markdown preview using the standalone inkwell CLI

local function inkwell_bin()
  if vim.g.inkwell_bin and vim.fn.executable(vim.g.inkwell_bin) == 1 then return vim.g.inkwell_bin end

  if vim.fn.executable "inkwell" == 1 then return "inkwell" end

  local local_bin = vim.fn.expand "~/code/zimakki/inkwell/inkwell"
  if vim.fn.executable(local_bin) == 1 then return local_bin end
end

local function notify_lines(prefix, lines, level)
  for _, line in ipairs(lines or {}) do
    if line and line ~= "" then vim.notify(prefix .. line, level or vim.log.levels.INFO) end
  end
end

local function run_inkwell(args, opts)
  opts = opts or {}
  local bin = inkwell_bin()

  if not bin then
    vim.notify("Inkwell: executable not found", vim.log.levels.ERROR)
    return
  end

  vim.fn.jobstart(vim.list_extend({ bin }, args), {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if opts.on_stdout then
        opts.on_stdout(data or {})
      else
        notify_lines("Inkwell: ", data)
      end
    end,
    on_stderr = function(_, data) notify_lines("Inkwell ERR: ", data, vim.log.levels.ERROR) end,
    on_exit = function(_, code)
      if opts.on_exit then opts.on_exit(code) end
    end,
  })
end

local function preview_current_file()
  run_inkwell({ "preview", vim.fn.expand "%:p", "--theme", vim.g.inkwell_theme or "dark" }, {
    on_stdout = function(data)
      for _, line in ipairs(data or {}) do
        if line and line ~= "" then vim.notify("Inkwell: " .. line) end
      end
    end,
    on_exit = function(code)
      if code ~= 0 then vim.notify("Inkwell preview failed with code " .. code, vim.log.levels.ERROR) end
    end,
  })
end

local function stop_daemon()
  run_inkwell({ "stop" }, {
    on_exit = function(code)
      if code ~= 0 then vim.notify("Inkwell stop failed with code " .. code, vim.log.levels.WARN) end
    end,
  })
end

local function show_status()
  run_inkwell({ "status" }, {
    on_stdout = function(data) notify_lines("Inkwell: ", data) end,
    on_exit = function(code)
      if code ~= 0 then vim.notify("Inkwell status failed with code " .. code, vim.log.levels.WARN) end
    end,
  })
end

return {
  "AstroNvim/astrocore",
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "markdown",
      callback = function(args)
        vim.keymap.set("n", "<leader>mp", preview_current_file, {
          buffer = args.buf,
          desc = "Inkwell preview",
        })

        vim.api.nvim_buf_create_user_command(args.buf, "InkwellPreview", preview_current_file, {
          desc = "Open current markdown file in inkwell preview",
        })

        vim.api.nvim_buf_create_user_command(args.buf, "InkwellStop", stop_daemon, {
          desc = "Stop the inkwell daemon",
        })

        vim.api.nvim_buf_create_user_command(args.buf, "InkwellStatus", show_status, {
          desc = "Show inkwell daemon status",
        })
      end,
    })
  end,
}
