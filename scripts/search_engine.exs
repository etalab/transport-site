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

  use Phoenix.HTML, only: [text_input: 2]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:title, "")
     |> assign(:format, "")
     |> assign(:mode, "")
     |> update_datasets(%{"config" => %{}})}
  end

  defp phx_vsn, do: Application.spec(:phoenix, :vsn)
  defp lv_vsn, do: Application.spec(:phoenix_live_view, :vsn)

  def render("live.html", assigns) do
    ~H"""
    <script src={"https://cdn.jsdelivr.net/npm/phoenix@#{phx_vsn()}/priv/static/phoenix.min.js"}>
    </script>
    <script src={"https://cdn.jsdelivr.net/npm/phoenix_live_view@#{lv_vsn()}/priv/static/phoenix_live_view.min.js"}>
    </script>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/css/bootstrap.min.css" rel="stylesheet" />
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/js/bootstrap.bundle.min.js">
    </script>
    <script>
      let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket)
      liveSocket.connect()
    </script>
    <style>
      * { font-size: 1.1em; }
    </style>
    {@inner_content}
    """
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 py-5 text-center">
      <.form :let={f} id="search" for={%{}} as={:config} phx-change="change_form" phx-submit="ignore">
        <div>
          {text_input(f, :title,
            value: @title,
            placeholder: "Title",
            autocorrect: "off"
          )}
          {text_input(f, :format,
            value: @format,
            placeholder: "Resource Format",
            autocorrect: "off"
          )}
          {text_input(f, :mode,
            value: @mode,
            placeholder: "Resource Mode",
            autocorrect: "off"
          )}
        </div>
      </.form>

      <p>
        {@datasets |> length} datasets found
      </p>
      <table class="table fs-6">
        <tbody>
          <%= for dataset <- @datasets do %>
            <tr>
              <td>{dataset.id}</td>
              <td style="min-width: 30em;">{dataset.title}</td>
              <td>{dataset.formats}</td>
              <td>{dataset.modes}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  import Ecto.Query

  def nil_if_blank(value) do
    value = (value || "") |> String.trim()
    if value == "", do: nil, else: value
  end

  def update_datasets(socket, params) do
    # NOTE: could be improved here to tap directly in the assigns
    datasets =
      Searcher.search(
        title: nil_if_blank(get_in(params, ["config", "title"])),
        format: nil_if_blank(get_in(params, ["config", "format"])),
        mode: nil_if_blank(get_in(params, ["config", "mode"]))
      )
      |> Enum.map(&Searcher.render(&1))

    assign(socket, :datasets, datasets)
  end

  def handle_event("change_form", params, socket) do
    {:noreply, update_datasets(socket, params)}
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
      preload: :resources
      #      limit: 10
    )
    |> DB.Repo.all()
  end

  def find_resource_history(resource_id) do
    from(rh in DB.ResourceHistory)
    |> where([rh], rh.resource_id == ^resource_id)
    |> order_by([rh], {:desc, rh.inserted_at})
    |> limit(1)
    |> DB.Repo.one()
  end

  def find_resource_metadata(resource_history_id) do
    from(rm in DB.ResourceMetadata)
    |> where([rm], rm.resource_history_id == ^resource_history_id)
    |> order_by([rh], {:desc, rh.inserted_at})
    |> limit(1)
    |> DB.Repo.one()
  end

  def compute_payload(%DB.Dataset{} = dataset) do
    # NOTE: not optimized for N+1 because performance is good enough for now

    modes =
      dataset.resources
      |> Enum.map(fn r ->
        rh_id = if x = find_resource_history(r.id), do: x.id, else: nil

        if rh_id != nil do
          rm = find_resource_metadata(rh_id)

          if rm != nil do
            rm.metadata["modes"]
          else
            nil
          end
        else
          nil
        end
      end)
      |> List.flatten()
      |> Enum.reject(&(&1 == nil))

    %{
      id: dataset.id,
      datagouv_id: dataset.datagouv_id,
      title: dataset.custom_title,
      description: dataset.description,
      formats: dataset.resources |> Enum.map(& &1.format),
      modes: modes
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

  # NOTE: could be DRYed with formats
  def maybe_search_resources_modes(query, nil), do: query

  def maybe_search_resources_modes(query, mode) do
    query
    |> where([d], fragment("search_payload #> Array['modes'] \\? ?", ^mode))
  end

  def search(options) do
    from(d in DB.Dataset)
    |> maybe_search_title(options[:title])
    |> maybe_search_resources_formats(options[:format])
    |> maybe_search_resources_modes(options[:mode])
    |> select([d], [:id, :custom_title, :search_payload])
    |> DB.Repo.all()
  end

  def render(%{} = item) do
    %{
      id: item.id,
      title: item.custom_title,
      formats: (item.search_payload["formats"] || []) |> Enum.join(", "),
      modes: (item.search_payload["modes"] || []) |> Enum.join(", ")
    }
  end

  def render(items) do
    IO.ANSI.Table.start([:id, :title, :formats])
    IO.ANSI.Table.format(items |> Enum.map(&render(&1)))
  end
end

if System.get_env("REINDEX") == "1" do
  SearchIndexer.reindex!()
end

# Uncomment for fancy ANSI-console rendering

# Searcher.search(title: "bibus")
# |> Searcher.render()

# Searcher.search(format: "SIRI")
# |> Searcher.render()

if System.get_env("RUN_SERVER") == "1" do
  {:ok, _} = Supervisor.start_link([Search.Endpoint], strategy: :one_for_one)
  Process.sleep(:infinity)
end

IO.puts("Done")
