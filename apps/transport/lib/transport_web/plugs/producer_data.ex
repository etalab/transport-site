defmodule TransportWeb.Plugs.ProducerData do
  @moduledoc """
  A Plug to fetch and assign dataset information and validation checks for authenticated producers.

  This plug intercepts the connection and checks if the current user has "producer"
  privileges. If they do, it retrieves the user's datasets and performs a series
  of data integrity checks, caching the results during 30 minutes to optimize
  performance.

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
      Transport.Cache.fetch(cache_key, fn -> DB.Dataset.datasets_for_user(conn) end, @cache_delay)
      |> maybe_delete(cache_key)

    assign(conn, :datasets_for_user, datasets)
  end

  defp maybe_delete({:error, _} = value, cache_key) do
    Cachex.del(@cache_name, cache_key)
    value
  end

  defp maybe_delete(value, _cache_key), do: value

  defp datasets_checks(%Plug.Conn{assigns: %{datasets_for_user: datasets, current_user: %{"id" => user_id}}} = conn) do
    checks =
      case datasets do
        [%DB.Dataset{} | _] = datasets ->
          Transport.Cache.fetch(
            "datasets_checks::#{user_id}",
            fn -> Enum.map(datasets, &Transport.DatasetChecks.check/1) end,
            @cache_delay
          )

        _ ->
          []
      end

    assign(conn, :datasets_checks, checks)
  end
end
