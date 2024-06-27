defmodule TransportWeb.API.V2.Controller do
  use Phoenix.Controller, namespace: TransportWeb
  import Ecto.Query

  @spec resources(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def resources(conn, params) do
    items =
      DB.Resource
      |> filter(params)
      |> DB.Repo.all()

    json(conn, format_items(items))
  end

  # TODO: reply HTTP 422 when something incorrect is detected
  def filter(query, params) do
    {declared_format, remaining} = Map.pop(params, "declared_format")
    %{} = remaining

    query
    |> ecto_filter("declared_format", parse_param("declared_format", declared_format))
  end

  def parse_param("declared_format", nil), do: nil

  def parse_param("declared_format", value) do
    {:ok, value} = PostgrestQueryParser.parse(value)
    value
  end

  defp ecto_filter(query, "declared_format", nil), do: query

  defp ecto_filter(query, "declared_format", [:eq, value]) do
    IO.puts("filtering where format is #{value}")

    query
    |> where([r], fragment("lower(?)", r.format) == ^value)
  end

  defp ecto_filter(query, "declared_format", [:in, values]) do
    query
    |> where([r], fragment("lower(?)", r.format) in ^values)
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
      dataset_id: item.dataset_id,
      declared_format: (item.format || "unknown") |> String.downcase(),
      title: item.title
    }
  end
end
