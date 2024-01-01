#! elixir

my_app_root = Path.join(__DIR__, "..")

Application.put_env(:search, Search.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 5001],
  server: true,
  live_view: [signing_salt: "aaaaaaaa"],
  secret_key_base: String.duplicate("a", 64)
)

Mix.install(
  [
    {:my_app, path: my_app_root, env: :dev},
    {:io_ansi_table, "~> 1.0"}
  ],
  config_path: Path.join(my_app_root, "config/config.exs"),
  lockfile: Path.join(my_app_root, "mix.lock")
)

# NOTE: wondering if Flop (https://github.com/woylie/flop) could be a better fit than Scrivener (which is hardly maintained)
# It provides cursor-based pagination as well as regular limit/offset stuff.

defmodule Search.ErrorView do
  def render(template, _), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule Search.HomeLive do
  use Phoenix.LiveView, layout: {__MODULE__, :live}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :count, 0)}
  end

  defp phx_vsn, do: Application.spec(:phoenix, :vsn)
  defp lv_vsn, do: Application.spec(:phoenix_live_view, :vsn)

  def render("live.html", assigns) do
    ~H"""
    <script src={"https://cdn.jsdelivr.net/npm/phoenix@#{phx_vsn()}/priv/static/phoenix.min.js"}>
    </script>
    <script src={"https://cdn.jsdelivr.net/npm/phoenix_live_view@#{lv_vsn()}/priv/static/phoenix_live_view.min.js"}>
    </script>
    <script>
      let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket)
      liveSocket.connect()
    </script>
    <style>
      * { font-size: 1.1em; }
    </style>
    <%= @inner_content %>
    """
  end

  def render(assigns) do
    ~H"""
    <%= @count %>
    <button phx-click="inc">+</button>
    <button phx-click="dec">-</button>
    """
  end

  def handle_event("inc", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count + 1)}
  end

  def handle_event("dec", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count - 1)}
  end
end

defmodule Search.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  scope "/", Search do
    pipe_through(:browser)

    live("/", HomeLive, :index)
  end
end

defmodule Search.Endpoint do
  use Phoenix.Endpoint, otp_app: :search
  socket("/live", Phoenix.LiveView.Socket)
  plug(Search.Router)
end

defmodule SearchIndexer do
  import Ecto.Query

  def fetch_items do
    from(d in DB.Dataset,
      join: r in assoc(d, :resources),
      preload: :resources
    )
    |> DB.Repo.all()
  end

  def compute_payload(%DB.Dataset{} = dataset) do
    %{
      id: dataset.id,
      datagouv_id: dataset.datagouv_id,
      title: dataset.custom_title,
      description: dataset.description,
      formats: dataset.resources |> Enum.map(& &1.format)
    }
  end

  def reindex! do
    # NOTE: much, much too slow for my taste, should be bulked and/or parallelized
    fetch_items()
    |> Enum.map(&{&1, compute_payload(&1)})
    |> Enum.each(fn {%DB.Dataset{} = d, %{} = payload} ->
      Ecto.Changeset.change(d, %{search_payload: payload})
      |> DB.Repo.update!()
    end)
  end
end

defmodule Searcher do
  import Ecto.Query

  def maybe_search_title(query, nil), do: query

  def maybe_search_title(query, search_title) do
    safe_like_title = "%" <> DB.Contact.safe_like_pattern(search_title) <> "%"

    query
    |> where([d], fragment("search_payload->>'title' ilike ?", ^safe_like_title))
  end

  def maybe_search_resources_formats(query, nil), do: query

  def maybe_search_resources_formats(query, search_format) do
    query
    |> where([d], fragment("search_payload #> Array['formats'] \\? ?", ^search_format))
  end

  def search(options) do
    from(d in DB.Dataset)
    |> maybe_search_title(options[:title])
    |> maybe_search_resources_formats(options[:format])
    |> select([d], [:id, :custom_title, :search_payload])
    |> DB.Repo.all()
  end

  def render(%{} = item) do
    %{
      id: item.id,
      title: item.custom_title,
      formats: item.search_payload["formats"] |> Enum.join(", ")
    }
  end

  def render(items) do
    IO.ANSI.Table.start([:id, :title, :formats])
    IO.ANSI.Table.format(items |> Enum.map(&render(&1)))
  end
end

# SearchIndexer.reindex!()

# Searcher.search(title: "bibus")
# |> Searcher.render()

# Searcher.search(format: "SIRI")
# |> Searcher.render()

{:ok, _} = Supervisor.start_link([Search.Endpoint], strategy: :one_for_one)
Process.sleep(:infinity)
