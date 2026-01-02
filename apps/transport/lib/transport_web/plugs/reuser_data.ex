defmodule TransportWeb.Plugs.ReuserData do
  @moduledoc """
  A Plug to fetch and assign dataset information and validation checks for authenticated reusers.

  ## Cache busting

  Cached values are cleaned after 30 minutes.

  ## Assignments

  This plug adds the following keys to `conn.assigns`:

  * `:followed_datasets` - A list of dataset records followed by the current user.
  * `:followed_datasets_checks` - The results of validation logic run against those datasets.
  """
  import Plug.Conn

  @cache_delay :timer.minutes(30)

  def init(opts), do: opts

  def call(%Plug.Conn{} = conn, _opts) do
    conn |> followed_datasets() |> followed_datasets_checks()
  end

  defp followed_datasets(%Plug.Conn{assigns: %{current_contact: %DB.Contact{} = contact}} = conn) do
    datasets = contact |> DB.Repo.preload(:followed_datasets) |> Map.fetch!(:followed_datasets)

    assign(conn, :followed_datasets, datasets)
  end

  defp followed_datasets(%Plug.Conn{assigns: %{current_contact: nil}} = conn) do
    assign(conn, :followed_datasets, [])
  end

  defp followed_datasets_checks(
         %Plug.Conn{assigns: %{followed_datasets: datasets, current_user: %{"id" => user_id}}} = conn
       ) do
    cache_key = "followed_datasets_checks::#{user_id}"

    checks =
      case datasets do
        [%DB.Dataset{} | _] = datasets ->
          datasets_checks(datasets, cache_key)

        _ ->
          []
      end

    assign(conn, :followed_datasets_checks, checks)
  end

  defp datasets_checks(datasets, cache_key) do
    Transport.Cache.fetch(
      cache_key,
      fn ->
        Enum.map(datasets, fn %DB.Dataset{} = dataset -> Transport.DatasetChecks.check(dataset, :reuser) end)
      end,
      @cache_delay
    )
  end

  defp followed_datasets_checks(%Plug.Conn{} = conn), do: assign(conn, :followed_datasets_checks, [])
end
