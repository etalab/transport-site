defmodule TransportWeb.API.V2.Controller do
  use Phoenix.Controller, namespace: TransportWeb

  @spec resources(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def resources(conn, _params) do
    items = DB.Repo.all(DB.Resource)
    json(conn, format_items(items))
  end

  defp format_items(items) do
    items
    |> Enum.map(&format_item(&1))
  end

  defp format_item(%DB.Resource{} = item) do
    %{
      # despite potential stability issues:
      # https://github.com/etalab/transport-site/issues/1946
      #
      # the `datagouv_id` cannot be safely used to uniquely designate a resource:
      # https://github.com/etalab/transport-site/issues/4022
      #
      # so I'm exposing the primary key instead for the moment
      id: item.id,
      dataset_id: item.dataset_id
    }
end
end
