defmodule TransportWeb.Plugs.ProducerData do
  @moduledoc """
  A Plug to fetch and assign dataset information and validation checks for authenticated producers.

  This plug intercepts the connection and checks if the current user has "producer"
  privileges. If they do, it retrieves the user's datasets and performs a series
  of data integrity checks, caching the results during 30 minutes to optimize
  performance.

  ## Cache busting

  Cached values are cleaned after 30 minutes or immediately when performing a
  `POST` request within the Espace Producteur.

  ## Assignments

  This plug adds the following keys to `conn.assigns`:

  * `:datasets_for_user` - A list of dataset records associated with the current user.
  * `:datasets_checks` - The results of validation logic run against those datasets.
  """
  import Plug.Conn

  @cache_delay :timer.minutes(30)
  @cache_name Transport.Cache.Cachex.cache_name()

  def init(opts), do: opts

  def call(%Plug.Conn{} = conn, _opts) do
    if TransportWeb.Session.producer?(conn) do
      conn |> datasets_for_user() |> datasets_checks()
    else
      conn
    end
  end

  defp datasets_for_user(%Plug.Conn{assigns: %{current_user: %{"id" => user_id}}} = conn) do
    cache_key = "datasets_for_user::#{user_id}"

    datasets =
      maybe_skip_cache(conn, cache_key, fn -> DB.Dataset.datasets_for_user(conn) end)
      |> maybe_delete_if_error(cache_key)

    assign(conn, :datasets_for_user, datasets)
  end

  defp datasets_checks(%Plug.Conn{assigns: %{datasets_for_user: datasets, current_user: %{"id" => user_id}}} = conn) do
    cache_key = "datasets_checks::#{user_id}"

    checks =
      case datasets do
        [%DB.Dataset{} | _] = datasets ->
          datasets_checks(conn, cache_key, datasets)

        _ ->
          []
      end

    assign(conn, :datasets_checks, checks)
  end

  defp datasets_checks(conn, cache_key, datasets) do
    maybe_skip_cache(conn, cache_key, fn ->
      Enum.map(datasets, fn %DB.Dataset{} = dataset -> Transport.DatasetChecks.check(dataset, :producer) end)
    end)
  end

  defp maybe_delete_if_error({:error, _} = value, cache_key) do
    Cachex.del(@cache_name, cache_key)
    value
  end

  defp maybe_delete_if_error(value, _cache_key), do: value

  defp maybe_skip_cache(%Plug.Conn{method: method, request_path: request_path} = conn, cache_key, function) do
    in_espace_producteur? =
      String.starts_with?(request_path, TransportWeb.Router.Helpers.espace_producteur_path(conn, :espace_producteur))

    skip_cache? = method in ["PUT", "POST", "DELETE"] and in_espace_producteur?

    if skip_cache? do
      Cachex.del(@cache_name, cache_key)
      function.()
    else
      Transport.Cache.fetch(cache_key, function, @cache_delay)
    end
  end
end
