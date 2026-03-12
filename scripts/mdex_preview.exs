Mix.install([
  {:mdex, "~> 0.11"},
  {:bandit, "~> 1.10"},
  {:plug, "~> 1.19"},
  {:websock_adapter, "~> 0.5"},
  {:file_system, "~> 1.0"},
  {:jason, "~> 1.4"}
])

# ── WebSocket handler ──────────────────────────────────────

defmodule MdexPreview.WsHandler do
  @behaviour WebSock

  @impl true
  def init(_opts) do
    Registry.register(MdexPreview.Registry, :ws_clients, [])
    {:ok, %{}}
  end

  @impl true
  def handle_in({text, _opts}, state) when text == "ping", do: {:push, {:text, "pong"}, state}
  def handle_in(_message, state), do: {:ok, state}

  @impl true
  def handle_info({:reload, html}, state) do
    {:push, {:text, html}, state}
  end

  def handle_info(_msg, state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state), do: :ok
end

# ── File history ───────────────────────────────────────────

defmodule MdexPreview.History do
  use Agent

  def start_link(initial_path) do
    Agent.start_link(fn -> [initial_path] end, name: __MODULE__)
  end

  def push(path) do
    Agent.update(__MODULE__, fn history ->
      [path | Enum.reject(history, &(&1 == path))] |> Enum.take(20)
    end)
  end

  def list, do: Agent.get(__MODULE__, & &1)
end

# ── Markdown rendering ─────────────────────────────────────

defmodule MdexPreview.Render do
  @mdex_opts [
    extension: [
      strikethrough: true,
      table: true,
      autolink: true,
      tasklist: true,
      footnotes: true
    ],
    render: [unsafe_: true]
  ]

  def render(markdown) do
    # Replace mermaid fenced blocks with raw HTML divs before mdex processes them.
    # mdex passes raw HTML through with unsafe_: true, so the divs survive rendering.
    md =
      Regex.replace(~r/```mermaid\n(.*?)```/s, markdown, fn _, content ->
        escaped =
          content
          |> String.replace("&", "&amp;")
          |> String.replace("<", "&lt;")
          |> String.replace(">", "&gt;")

        "<pre class=\"mermaid\">#{escaped}</pre>"
      end)

    MDEx.to_html!(md, @mdex_opts)
  end
end

# ── File watcher ───────────────────────────────────────────

defmodule MdexPreview.Watcher do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def switch_file(path) do
    GenServer.call(__MODULE__, {:switch_file, Path.expand(path)})
  end

  @impl true
  def init(%{path: path}) do
    dir = Path.dirname(path)
    {:ok, watcher} = FileSystem.start_link(dirs: [dir])
    FileSystem.subscribe(watcher)
    {:ok, %{path: path, watcher: watcher}}
  end

  @impl true
  def handle_call({:switch_file, new_path}, _from, state) do
    # Stop old watcher and start a new one for the new file's directory
    if state.watcher, do: GenServer.stop(state.watcher)

    new_dir = Path.dirname(new_path)
    {:ok, watcher} = FileSystem.start_link(dirs: [new_dir])
    FileSystem.subscribe(watcher)

    :persistent_term.put(:mdex_file, new_path)
    MdexPreview.History.push(new_path)

    # Push initial render of new file
    html = new_path |> File.read!() |> MdexPreview.Render.render()
    broadcast(html)

    {:reply, :ok, %{state | path: new_path, watcher: watcher}}
  end

  @impl true
  def handle_info({:file_event, _pid, {changed_path, events}}, state) do
    if Path.expand(changed_path) == Path.expand(state.path) and :modified in events do
      html = state.path |> File.read!() |> MdexPreview.Render.render()
      broadcast(html)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp broadcast(html) do
    Registry.dispatch(MdexPreview.Registry, :ws_clients, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:reload, html})
    end)
  end
end

# ── Plug router ────────────────────────────────────────────

defmodule MdexPreview.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/" do
    file_path = :persistent_term.get(:mdex_file)
    theme = :persistent_term.get(:mdex_theme)

    html = file_path |> File.read!() |> MdexPreview.Render.render()

    filename = Path.basename(file_path)
    page = html_page(html, filename, theme)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, page)
  end

  get "/ws" do
    conn
    |> WebSockAdapter.upgrade(MdexPreview.WsHandler, [], timeout: :infinity)
    |> halt()
  end

  get "/switch" do
    new_path = conn.query_string |> URI.decode()

    if File.exists?(new_path) do
      MdexPreview.Watcher.switch_file(new_path)

      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "Switched to #{new_path}")
    else
      send_resp(conn, 404, "File not found: #{new_path}")
    end
  end

  get "/files" do
    current = :persistent_term.get(:mdex_file)
    dir = Path.dirname(current)

    siblings =
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".md"))
      |> Enum.map(&Path.join(dir, &1))
      |> Enum.sort()

    recent = MdexPreview.History.list()

    json = Jason.encode!(%{current: current, recent: recent, siblings: siblings, dir: dir})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, json)
  end

  get "/css/markdown-wide.css" do
    css_dir = :persistent_term.get(:mdex_css_dir)
    css_path = Path.join(css_dir, "markdown-wide.css")

    case File.read(css_path) do
      {:ok, css} ->
        conn
        |> put_resp_content_type("text/css")
        |> send_resp(200, css)

      {:error, _} ->
        send_resp(conn, 404, "CSS file not found")
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp html_page(content, filename, theme) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{filename}</title>
      <link rel="stylesheet" href="/css/markdown-wide.css">
      <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
      <style>
        #page-header { cursor: pointer; user-select: none; position: relative; }
        #page-header h3::after { content: ' ▾'; font-size: 0.7em; opacity: 0.5; }

        #file-picker {
          position: fixed; top: 0; right: -380px; width: 360px; height: 100vh;
          background: var(--bg-surface); border-left: 1px solid var(--border);
          box-shadow: -4px 0 20px rgba(0,0,0,0.15);
          transition: right 0.25s ease; z-index: 1000;
          display: flex; flex-direction: column;
          font-family: "Outfit", system-ui, sans-serif;
        }
        #file-picker.open { right: 0; }

        #file-picker-header {
          padding: 1em 1.2em; border-bottom: 1px solid var(--border);
          display: flex; justify-content: space-between; align-items: center;
        }
        #file-picker-header h4 {
          margin: 0; font-size: 0.85em; font-weight: 600;
          text-transform: uppercase; letter-spacing: 0.05em;
          color: var(--text-muted);
          font-family: "Bricolage Grotesque", system-ui, sans-serif;
        }
        #file-picker-close {
          background: none; border: none; color: var(--text-muted);
          font-size: 1.4em; cursor: pointer; padding: 0 0.2em;
          line-height: 1;
        }
        #file-picker-close:hover { color: var(--text); }

        #file-picker-body { overflow-y: auto; flex: 1; padding: 0.5em 0; }

        .file-section {
          padding: 0.6em 1.2em 0.2em;
          font-size: 0.75em; font-weight: 600;
          text-transform: uppercase; letter-spacing: 0.06em;
          color: var(--text-muted);
          font-family: "Bricolage Grotesque", system-ui, sans-serif;
        }

        .file-item {
          display: block; padding: 0.5em 1.2em;
          color: var(--text-secondary); text-decoration: none;
          font-size: 0.9em; cursor: pointer;
          border-left: 3px solid transparent;
          transition: background 0.1s, border-color 0.1s;
        }
        .file-item:hover {
          background: var(--bg-hover); color: var(--text);
          border-left-color: var(--link);
        }
        .file-item.active {
          color: var(--link); font-weight: 500;
          border-left-color: var(--link);
          background: var(--bg-hover);
        }
        .file-item .file-dir {
          font-size: 0.8em; color: var(--text-muted);
          display: block; margin-top: 0.15em;
        }

        #file-picker-overlay {
          position: fixed; top: 0; left: 0; width: 100%; height: 100%;
          z-index: 999; display: none;
        }
        #file-picker-overlay.open { display: block; }
      </style>
    </head>
    <body>
      <div data-theme="#{theme}">
        <div id="page-header">
          <h3 id="header-title">#{filename}</h3>
        </div>
        <div id="page-ctn">
          #{content}
        </div>
      </div>

      <div id="file-picker-overlay"></div>
      <div id="file-picker">
        <div id="file-picker-header">
          <h4>Files</h4>
          <button id="file-picker-close">&times;</button>
        </div>
        <div id="file-picker-body"></div>
      </div>

      <script>
        (function() {
          var ctn = document.getElementById('page-ctn');
          var picker = document.getElementById('file-picker');
          var pickerBody = document.getElementById('file-picker-body');
          var overlay = document.getElementById('file-picker-overlay');
          var headerTitle = document.getElementById('header-title');
          var ws;

          mermaid.initialize({ startOnLoad: false, theme: '#{theme}' === 'dark' ? 'dark' : 'default' });

          function renderMermaid() {
            var blocks = ctn.querySelectorAll('pre.mermaid');
            if (blocks.length > 0) {
              blocks.forEach(function(el) { el.removeAttribute('data-processed'); });
              mermaid.run({ nodes: blocks });
            }
          }

          // ── File picker ──────────────────────────────

          function closePicker() {
            picker.classList.remove('open');
            overlay.classList.remove('open');
          }

          function openPicker() {
            picker.classList.add('open');
            overlay.classList.add('open');
            loadFiles();
          }

          function switchFile(path) {
            fetch('/switch?' + encodeURIComponent(path))
              .then(function(r) {
                if (r.ok) {
                  headerTitle.textContent = path.split('/').pop();
                  document.title = path.split('/').pop();
                  closePicker();
                }
              });
          }

          function loadFiles() {
            fetch('/files').then(function(r) { return r.json(); }).then(function(data) {
              var html = '';
              var seen = {};

              // Recent files
              if (data.recent.length > 0) {
                html += '<div class="file-section">Recent</div>';
                data.recent.forEach(function(f) {
                  seen[f] = true;
                  var name = f.split('/').pop();
                  var dir = f.substring(0, f.length - name.length - 1);
                  var cls = f === data.current ? 'file-item active' : 'file-item';
                  html += '<a class="' + cls + '" data-path="' + f + '">'
                    + name + '<span class="file-dir">' + dir + '</span></a>';
                });
              }

              // Sibling files (exclude already shown)
              var siblings = data.siblings.filter(function(f) { return !seen[f]; });
              if (siblings.length > 0) {
                html += '<div class="file-section">' + data.dir.split('/').pop() + '/</div>';
                siblings.forEach(function(f) {
                  var name = f.split('/').pop();
                  html += '<a class="file-item" data-path="' + f + '">' + name + '</a>';
                });
              }

              pickerBody.innerHTML = html;
            });
          }

          document.getElementById('page-header').addEventListener('click', function(e) {
            if (picker.classList.contains('open')) closePicker();
            else openPicker();
          });

          overlay.addEventListener('click', closePicker);
          document.getElementById('file-picker-close').addEventListener('click', closePicker);

          pickerBody.addEventListener('click', function(e) {
            var item = e.target.closest('.file-item');
            if (item && !item.classList.contains('active')) {
              switchFile(item.dataset.path);
            }
          });

          document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape') closePicker();
          });

          // ── WebSocket ────────────────────────────────

          function connect() {
            ws = new WebSocket('ws://' + location.host + '/ws');
            ws.onmessage = function(e) {
              if (e.data === 'pong') return;
              ctn.innerHTML = e.data;
              renderMermaid();
            };
            ws.onclose = function() {
              setTimeout(connect, 1000);
            };
            ws.onopen = function() {
              setInterval(function() {
                if (ws.readyState === 1) ws.send('ping');
              }, 30000);
            };
          }
          connect();
          renderMermaid();

          document.addEventListener('keydown', function(e) {
            if (e.ctrlKey && e.shiftKey && e.key === 'T') {
              var el = document.querySelector('[data-theme]');
              var isDark = el.dataset.theme === 'dark';
              el.dataset.theme = isDark ? 'light' : 'dark';
              mermaid.initialize({ startOnLoad: false, theme: isDark ? 'default' : 'dark' });
              renderMermaid();
            }
          });
        })();
      </script>
    </body>
    </html>
    """
  end
end

# ── Main ───────────────────────────────────────────────────

{opts, args, _} =
  OptionParser.parse(System.argv(),
    strict: [port: :integer, theme: :string, css_dir: :string]
  )

file_path =
  case args do
    [path | _] -> Path.expand(path)
    [] ->
      IO.puts("Usage: elixir mdex_preview.exs <file.md> [--port 4123] [--theme dark] [--css-dir /path/to/css]")
      System.halt(1)
  end

unless File.exists?(file_path) do
  IO.puts("Error: file not found: #{file_path}")
  System.halt(1)
end

port = Keyword.get(opts, :port, 4123)
theme = Keyword.get(opts, :theme, "dark")
css_dir = Keyword.get(opts, :css_dir, Path.join(Path.dirname(__ENV__.file), "../css"))

:persistent_term.put(:mdex_file, file_path)
:persistent_term.put(:mdex_theme, theme)
:persistent_term.put(:mdex_css_dir, css_dir)

{:ok, _} = Registry.start_link(keys: :duplicate, name: MdexPreview.Registry)
{:ok, _} = MdexPreview.History.start_link(file_path)
{:ok, _} = MdexPreview.Watcher.start_link(%{path: file_path})
{:ok, bandit} = Bandit.start_link(plug: MdexPreview.Router, port: port)

IO.puts("MdexPreview running at http://localhost:#{port} for #{file_path}")
System.cmd("open", ["http://localhost:#{port}"])

# Trap shutdown signals so Bandit releases the port before exit
Process.flag(:trap_exit, true)

receive do
  {:EXIT, _, _} ->
    IO.puts("Shutting down...")
    Supervisor.stop(bandit)
end
