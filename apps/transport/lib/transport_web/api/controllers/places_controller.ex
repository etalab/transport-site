defmodule TransportWeb.API.PlacesController do
  use TransportWeb, :controller
  alias DB.{Place, Repo}
  alias Helpers
  alias OpenApiSpex.Operation
  alias TransportWeb.API.Schemas.AutocompleteResponse
  import Ecto.{Query}

  @spec open_api_operation(any) :: Operation.t()
  def open_api_operation(action), do: apply(__MODULE__, :"#{action}_operation", [])

  @spec get_result_url(Plug.Conn.t(), %Place{}) :: binary()
  defp get_result_url(conn, %Place{:place_id => id, :type => "commune"}), do: dataset_path(conn, :by_commune_insee, id)
  defp get_result_url(conn, %Place{:place_id => id, :type => "region"}), do: dataset_path(conn, :by_region, id)
  defp get_result_url(conn, %Place{:place_id => id, :type => "aom"}), do: dataset_path(conn, :by_aom, id)

  defp get_result_url(conn, %Place{:place_id => id, :type => "feature"}),
    do: dataset_path(conn, :index, "features[]": id)

  defp get_result_url(conn, %Place{:place_id => id, :type => "mode"}), do: dataset_path(conn, :index, "modes[]": id)

  @spec autocomplete(Plug.Conn.t(), map) :: Plug.Conn.t()
  def autocomplete(%Plug.Conn{} = conn, %{"q" => query}) do
    query =
      query
      # we replace '-' to ' ' because we also did this transformation for indexed_name
      |> String.replace("-", " ")
      # we replace ' ' to '%' to search for composite name to be easily searchable
      # we can look for "d'Urfé" with either "d'urfe" or "d urfe",
      # or "ile de france" with pattern like "i d f"
      |> String.replace(" ", "%")

    query = "%#{query}%"

    places =
      Place
      |> where([p], fragment("indexed_name ilike unaccent(?)", ^query))
      |> order_by(asc: fragment("CASE type
          when 'feature' then 1
          when 'mode' then 2
          when 'region' then 3
          when 'aom' then 4
          else 4 END"))
      |> order_by(desc: fragment("similarity(indexed_name, unaccent(?))", ^query))
      |> limit(10)
      |> Repo.all()

    results =
      places
      |> Enum.map(fn res ->
        %{name: res.nom, type: res.type, url: get_result_url(conn, res)}
      end)

    conn
    |> assign(:data, results)
    |> render()
  end

  @spec autocomplete_operation() :: Operation.t()
  def autocomplete_operation do
    %Operation{
      tags: ["datasets"],
      summary: "Autocomplete search for datasets",
      description: "Given a search input, return potentialy corresponding results with the associated url",
      operationId: "API.DatasetController.datasets_autocomplete",
      parameters: [Operation.parameter(:q, :path, :string, "query")],
      responses: %{
        200 => Operation.response("Dataset", "application/json", AutocompleteResponse)
      }
    }
  end
end
