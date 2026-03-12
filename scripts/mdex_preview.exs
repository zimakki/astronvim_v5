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

# ── Search & fuzzy matching ───────────────────────────────

defmodule MdexPreview.Search do
  @moduledoc """
  Indexes markdown files by filename and H1 title.
  Provides fuzzy search across both fields.
  """

  @doc """
  Extract the first H1 title from a markdown file.
  Reads up to 50 lines, returns the text of the first `# ...` line, or nil.
  """
  def extract_title(path) do
    path
    |> File.stream!()
    |> Stream.take(50)
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^#\s+(.+)$/, String.trim_trailing(line)) do
        [_, title] -> String.trim(title)
        nil -> nil
      end
    end)
  rescue
    _ -> nil
  end

  @doc """
  Score a candidate string against a query using fuzzy subsequence matching.
  Returns 0 if the query chars don't all appear in order.
  Higher scores = better match (consecutive chars, early position).
  """
  def fuzzy_score("", _candidate), do: 0
  def fuzzy_score(_query, nil), do: 0
  def fuzzy_score(_query, ""), do: 0

  def fuzzy_score(query, candidate) do
    q_chars = query |> String.downcase() |> String.graphemes()
    c_chars = candidate |> String.downcase() |> String.graphemes()

    case do_match(q_chars, c_chars, 0, 0, 0, nil, false) do
      nil -> 0
      {matched, consec_bonus, first_pos} ->
        position_bonus = max(0, 2 - first_pos)
        matched + consec_bonus + position_bonus
    end
  end

  # All query chars matched
  defp do_match([], _c, matched, cb, _idx, fp, _prev),
    do: {matched, cb, fp || 0}

  # Ran out of candidate chars before matching all query chars
  defp do_match(_q, [], _m, _cb, _idx, _fp, _prev), do: nil

  # Query char matches candidate char — award consecutive bonus if previous was also a match
  defp do_match([q | qr], [c | cr], matched, cb, idx, fp, prev) when q == c do
    new_fp = fp || idx
    new_cb = if prev, do: cb + 3, else: cb
    do_match(qr, cr, matched + 1, new_cb, idx + 1, new_fp, true)
  end

  # No match — advance candidate, reset consecutive flag
  defp do_match(q, [_c | cr], matched, cb, idx, fp, _prev) do
    do_match(q, cr, matched, cb, idx + 1, fp, false)
  end

  @doc """
  Build the full list of searchable files: recent history + siblings of current file.
  Deduplicates (recent takes priority). Extracts H1 title from each file.
  """
  def list_files do
    current = :persistent_term.get(:mdex_file)
    dir = Path.dirname(current)
    recent = MdexPreview.History.list()

    recent_entries =
      recent
      |> Enum.filter(&File.exists?/1)
      |> Enum.map(fn path ->
        %{
          path: path,
          filename: Path.basename(path),
          title: extract_title(path),
          section: :recent,
          active: path == current
        }
      end)

    recent_paths = MapSet.new(recent, & &1)

    sibling_entries =
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".md"))
      |> Enum.map(&Path.join(dir, &1))
      |> Enum.reject(&MapSet.member?(recent_paths, &1))
      |> Enum.sort()
      |> Enum.map(fn path ->
        %{
          path: path,
          filename: Path.basename(path),
          title: extract_title(path),
          section: :sibling,
          active: path == current
        }
      end)

    recent_entries ++ sibling_entries
  end

  @doc """
  Search files by query. Empty query returns all files.
  Non-empty query fuzzy-matches against filename and title, returns ranked results.
  """
  def search(""), do: list_files()
  def search(nil), do: list_files()

  def search(query) do
    list_files()
    |> Enum.map(fn entry ->
      filename_score = fuzzy_score(query, entry.filename)
      title_score = fuzzy_score(query, entry.title) * 1.2
      score = max(filename_score, title_score)
      {entry, score}
    end)
    |> Enum.reject(fn {_entry, score} -> score == 0 end)
    |> Enum.sort_by(fn {_entry, score} -> score end, :desc)
    |> Enum.take(50)
    |> Enum.map(fn {entry, _score} -> entry end)
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
    conn = Plug.Conn.fetch_query_params(conn)
    new_path = conn.query_params["path"]

    cond do
      is_nil(new_path) ->
        send_resp(conn, 400, "Missing path parameter")

      not File.exists?(new_path) ->
        send_resp(conn, 404, "File not found: #{new_path}")

      true ->
        MdexPreview.Watcher.switch_file(new_path)

        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, "Switched to #{new_path}")
    end
  end

  get "/search" do
    conn = Plug.Conn.fetch_query_params(conn)
    query = conn.query_params["q"] || ""

    results = MdexPreview.Search.search(query)

    json = Jason.encode!(results)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, json)
  end

  get "/preview" do
    conn = Plug.Conn.fetch_query_params(conn)
    path = case conn.query_params["path"] do
      nil -> nil
      p -> Path.expand(p)
    end

    cond do
      is_nil(path) ->
        send_resp(conn, 400, "Missing path parameter")

      not String.ends_with?(path, ".md") ->
        send_resp(conn, 400, "Path must end with .md")

      not File.exists?(path) ->
        send_resp(conn, 404, "File not found")

      true ->
        # Validate path is in allowed set (recent or sibling)
        allowed =
          MdexPreview.History.list() ++
            (Path.dirname(:persistent_term.get(:mdex_file))
             |> File.ls!()
             |> Enum.filter(&String.ends_with?(&1, ".md"))
             |> Enum.map(&Path.join(Path.dirname(:persistent_term.get(:mdex_file)), &1)))

        if path in allowed do
          html = path |> File.read!() |> MdexPreview.Render.render()

          conn
          |> put_resp_content_type("text/html")
          |> send_resp(200, html)
        else
          send_resp(conn, 403, "Path not in allowed file set")
        end
    end
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
    safe_filename = filename
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")
      |> String.replace("\"", "&quot;")

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{safe_filename}</title>
      <link rel="stylesheet" href="/css/markdown-wide.css">
      <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
      <style>
        #page-header { cursor: pointer; user-select: none; position: relative; }
        #page-header h3::after { content: ' ▾'; font-size: 0.7em; opacity: 0.5; }

        /* ── Picker overlay ── */
        #picker-overlay {
          position: fixed; top: 0; left: 0; width: 100%; height: 100%;
          background: rgba(0,0,0,0.6); z-index: 1000;
          display: none; align-items: center; justify-content: center;
        }
        #picker-overlay.open { display: flex; }

        #picker {
          width: 90vw; height: 85vh; max-width: 1400px;
          background: #16161e; border-radius: 8px;
          border: 1px solid #2f334d;
          display: flex; flex-direction: column;
          font-family: 'SF Mono', monospace; font-size: 13px;
          color: #c0caf5; overflow: hidden;
          box-shadow: 0 20px 60px rgba(0,0,0,0.5);
        }

        #picker-search {
          padding: 12px 16px; border-bottom: 1px solid #2f334d;
          display: flex; align-items: center; gap: 8px;
        }
        #picker-search-icon { color: #565f89; }
        #picker-search input {
          flex: 1; background: none; border: none; outline: none;
          color: #7aa2f7; font-size: 14px; font-family: inherit;
        }
        #picker-search input::placeholder { color: #565f89; }
        #picker-search .hint { color: #565f89; font-size: 11px; }

        #picker-body {
          display: flex; flex: 1; min-height: 0;
        }

        #picker-list {
          width: 35%; border-right: 1px solid #2f334d;
          overflow-y: auto; display: flex; flex-direction: column;
        }

        .picker-section {
          padding: 8px 12px 4px; font-size: 10px;
          text-transform: uppercase; letter-spacing: 0.08em;
          color: #565f89; font-family: system-ui;
        }

        .picker-item {
          padding: 6px 12px; cursor: pointer;
          border-left: 3px solid transparent;
        }
        .picker-item:hover { background: rgba(122,162,247,0.06); }
        .picker-item.selected {
          background: rgba(122,162,247,0.12);
          border-left-color: #7aa2f7;
        }
        .picker-item-title {
          color: #c0caf5; font-size: 13px; font-weight: 500;
          font-family: system-ui;
        }
        .picker-item.selected .picker-item-title { color: #c0caf5; }
        .picker-item:not(.selected) .picker-item-title { color: #a9b1d6; }
        .picker-item-file {
          color: #565f89; font-size: 11px; margin-top: 2px;
        }

        #picker-status {
          margin-top: auto; padding: 8px 12px;
          border-top: 1px solid #2f334d;
          font-size: 11px; color: #565f89; font-family: system-ui;
        }

        #picker-preview {
          width: 65%; overflow-y: auto; padding: 24px 32px;
          font-family: 'Outfit', system-ui, sans-serif;
        }
        #picker-preview .preview-unavailable {
          color: #565f89; font-style: italic;
          display: flex; align-items: center; justify-content: center;
          height: 100%;
        }
      </style>
    </head>
    <body>
      <div data-theme="#{theme}">
        <div id="page-header">
          <h3 id="header-title">#{safe_filename}</h3>
        </div>
        <div id="page-ctn">
          #{content}
        </div>
      </div>

      <div id="picker-overlay">
        <div id="picker">
          <div id="picker-search">
            <span id="picker-search-icon">&#9906;</span>
            <input type="text" id="picker-input" placeholder="Search files and titles..." autocomplete="off" />
            <span class="hint">ESC to close</span>
          </div>
          <div id="picker-body">
            <div id="picker-list">
              <div id="picker-list-items"></div>
              <div id="picker-status"></div>
            </div>
            <div id="picker-preview">
              <div class="preview-unavailable">Select a file to preview</div>
            </div>
          </div>
        </div>
      </div>

      <script>
        (function() {
          var ctn = document.getElementById('page-ctn');
          var headerTitle = document.getElementById('header-title');
          var pickerOverlay = document.getElementById('picker-overlay');
          var pickerInput = document.getElementById('picker-input');
          var pickerListItems = document.getElementById('picker-list-items');
          var pickerStatus = document.getElementById('picker-status');
          var pickerPreview = document.getElementById('picker-preview');
          var ws, pingInterval;
          var currentFiles = [];
          var selectedIndex = 0;
          var searchTimer = null;
          var previewTimer = null;
          var previewController = null;

          mermaid.initialize({ startOnLoad: false, theme: '#{theme}' === 'dark' ? 'dark' : 'default' });

          function renderMermaid() {
            var blocks = ctn.querySelectorAll('pre.mermaid');
            if (blocks.length > 0) {
              blocks.forEach(function(el) { el.removeAttribute('data-processed'); });
              mermaid.run({ nodes: blocks });
            }
          }

          // ── Picker ────────────────────────────────────

          function openPicker() {
            pickerOverlay.classList.add('open');
            pickerInput.value = '';
            pickerInput.focus();
            selectedIndex = 0;
            loadSearch('');
          }

          function closePicker() {
            pickerOverlay.classList.remove('open');
            pickerInput.blur();
            currentFiles = [];
            pickerListItems.innerHTML = '';
            pickerPreview.innerHTML = '<div class="preview-unavailable">Select a file to preview</div>';
          }

          function loadSearch(query) {
            if (previewController) { previewController.abort(); previewController = null; }
            fetch('/search?q=' + encodeURIComponent(query))
              .then(function(r) { return r.json(); })
              .then(function(files) {
                currentFiles = files;
                selectedIndex = 0;
                renderFileList();
                loadPreview();
              })
              .catch(function() {});
          }

          function renderFileList() {
            var html = '';
            var currentSection = null;
            currentFiles.forEach(function(f, i) {
              if (f.section !== currentSection) {
                currentSection = f.section;
                var label = f.section === 'recent' ? 'Recent' : (f.path.split('/').slice(-2, -1)[0] + '/');
                html += '<div class="picker-section">' + label + '</div>';
              }
              var cls = i === selectedIndex ? 'picker-item selected' : 'picker-item';
              var title = f.title || f.filename;
              html += '<div class="' + cls + '" data-index="' + i + '">'
                + '<div class="picker-item-title">' + escapeHtml(title) + '</div>'
                + '<div class="picker-item-file">' + escapeHtml(f.filename) + '</div>'
                + '</div>';
            });
            pickerListItems.innerHTML = html;
            pickerStatus.textContent = currentFiles.length + ' files \u00b7 \u2191\u2193 navigate \u00b7 \u21b5 open';

            // Scroll selected into view
            var sel = pickerListItems.querySelector('.selected');
            if (sel) sel.scrollIntoView({ block: 'nearest' });
          }

          function loadPreview() {
            if (previewTimer) clearTimeout(previewTimer);
            if (!currentFiles.length) {
              pickerPreview.innerHTML = '<div class="preview-unavailable">No files found</div>';
              return;
            }
            previewTimer = setTimeout(function() {
              var file = currentFiles[selectedIndex];
              if (!file) return;
              if (previewController) previewController.abort();
              previewController = new AbortController();
              fetch('/preview?path=' + encodeURIComponent(file.path), { signal: previewController.signal })
                .then(function(r) {
                  if (!r.ok) throw new Error('Preview failed');
                  return r.text();
                })
                .then(function(html) {
                  pickerPreview.innerHTML = html;
                })
                .catch(function(e) {
                  if (e.name !== 'AbortError') {
                    pickerPreview.innerHTML = '<div class="preview-unavailable">Preview unavailable</div>';
                  }
                });
            }, 100);
          }

          function selectFile() {
            var file = currentFiles[selectedIndex];
            if (!file) return;
            fetch('/switch?path=' + encodeURIComponent(file.path))
              .then(function(r) {
                if (r.ok) {
                  headerTitle.textContent = file.filename;
                  document.title = file.filename;
                  closePicker();
                }
              });
          }

          function escapeHtml(str) {
            var d = document.createElement('div');
            d.textContent = str;
            return d.innerHTML;
          }

          // ── Picker events ─────────────────────────────

          pickerInput.addEventListener('input', function() {
            if (searchTimer) clearTimeout(searchTimer);
            searchTimer = setTimeout(function() {
              loadSearch(pickerInput.value);
            }, 150);
          });

          pickerInput.addEventListener('keydown', function(e) {
            if (e.key === 'ArrowDown') {
              e.preventDefault();
              if (selectedIndex < currentFiles.length - 1) {
                selectedIndex++;
                renderFileList();
                loadPreview();
              }
            } else if (e.key === 'ArrowUp') {
              e.preventDefault();
              if (selectedIndex > 0) {
                selectedIndex--;
                renderFileList();
                loadPreview();
              }
            } else if (e.key === 'Enter') {
              e.preventDefault();
              selectFile();
            }
          });

          pickerListItems.addEventListener('click', function(e) {
            var item = e.target.closest('.picker-item');
            if (item) {
              var idx = parseInt(item.dataset.index, 10);
              if (idx === selectedIndex) {
                selectFile();
              } else {
                selectedIndex = idx;
                renderFileList();
                loadPreview();
              }
            }
          });

          pickerOverlay.addEventListener('click', function(e) {
            if (e.target === pickerOverlay) closePicker();
          });

          // ── Global keyboard ───────────────────────────

          document.getElementById('page-header').addEventListener('click', function() {
            if (pickerOverlay.classList.contains('open')) {
              pickerInput.focus();
            } else {
              openPicker();
            }
          });

          document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape' && pickerOverlay.classList.contains('open')) {
              closePicker();
              return;
            }
            if (e.ctrlKey && e.key === 'p') {
              e.preventDefault();
              if (pickerOverlay.classList.contains('open')) {
                pickerInput.focus();
              } else {
                openPicker();
              }
              return;
            }
            if (e.ctrlKey && e.shiftKey && e.key === 'T') {
              var el = document.querySelector('[data-theme]');
              var isDark = el.dataset.theme === 'dark';
              el.dataset.theme = isDark ? 'light' : 'dark';
              mermaid.initialize({ startOnLoad: false, theme: isDark ? 'default' : 'dark' });
              renderMermaid();
            }
          });

          // ── WebSocket ─────────────────────────────────

          function connect() {
            ws = new WebSocket('ws://' + location.host + '/ws');
            ws.onmessage = function(e) {
              if (e.data === 'pong') return;
              ctn.innerHTML = e.data;
              renderMermaid();
            };
            ws.onclose = function() {
              if (pingInterval) { clearInterval(pingInterval); pingInterval = null; }
              setTimeout(connect, 1000);
            };
            ws.onopen = function() {
              if (pingInterval) clearInterval(pingInterval);
              pingInterval = setInterval(function() {
                if (ws.readyState === 1) ws.send('ping');
              }, 30000);
            };
          }
          connect();
          renderMermaid();
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
