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

  def search(term) do
    from(d in DB.Dataset)
    |> where([d], fragment("search_payload->>'title' ilike ?", ^term))
    |> select([d], [:custom_title])
    |> DB.Repo.all()
  end

  def render(items) do
    IO.ANSI.Table.start([:id, :custom_title])
    IO.ANSI.Table.format(items)
  end
end

# SearchIndexer.reindex!()

Searcher.search("%bibus%")
|> Searcher.render()
