#! elixir

my_app_root = Path.join(__DIR__, "..")

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

Searcher.search(title: "bibus")
|> Searcher.render()

Searcher.search(format: "SIRI")
|> Searcher.render()
