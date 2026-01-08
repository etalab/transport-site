defmodule TransportWeb.API.AutocompleteController do
  use TransportWeb, :controller
  alias Helpers
  alias OpenApiSpex.Operation
  import Ecto.Query

  @spec open_api_operation(any) :: Operation.t()
  def open_api_operation(action), do: apply(__MODULE__, :"#{action}_operation", [])

  @spec get_result_url(Plug.Conn.t(), DB.Autocomplete.t()) :: binary()
  defp get_result_url(conn, %DB.Autocomplete{:place_id => id, :type => "region"}),
    do: dataset_path(conn, :by_region, id)

  defp get_result_url(conn, %DB.Autocomplete{:place_id => id, :type => "departement"}),
    do: dataset_path(conn, :by_departement_insee, id)

  defp get_result_url(conn, %DB.Autocomplete{:place_id => id, :type => "epci"}), do: dataset_path(conn, :by_epci, id)

  defp get_result_url(conn, %DB.Autocomplete{:place_id => id, :type => "commune"}),
    do: dataset_path(conn, :by_commune_insee, id)

  defp get_result_url(conn, %DB.Autocomplete{:place_id => id, :type => "feature"}),
    do: dataset_path(conn, :index, "features[]": id)

  defp get_result_url(conn, %DB.Autocomplete{:place_id => id, :type => "mode"}),
    do: dataset_path(conn, :index, "modes[]": id)

  defp get_result_url(conn, %DB.Autocomplete{:place_id => id, :type => "offer"}), do: dataset_path(conn, :by_offer, id)

  defp get_result_url(conn, %DB.Autocomplete{:place_id => format, :type => "format"}),
    do: dataset_path(conn, :index, format: format)

  defp get_result_url(conn, %DB.Autocomplete{:place_id => slug, :type => "dataset"}),
    do: dataset_path(conn, :details, slug)

  defp approx_search_query(query) do
    DB.Autocomplete
    |> order_by(desc: fragment("similarity(indexed_name, unaccent(?))", ^query))
    |> where([p], fragment("indexed_name % unaccent(?)", ^query))
    |> limit(10)
    |> DB.Repo.all()
  end

  @spec autocomplete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def autocomplete(%Plug.Conn{} = conn, params) do
    query =
      Map.get(params, "q", "")
      # we replace '-' to ' ' because we also did this transformation for indexed_name
      |> String.replace("-", " ")
      # we replace ' ' to '%' to search for composite name to be easily searchable
      # we can look for "d'Urfé" with either "d'urfe" or "d urfe",
      # or "ile de france" with pattern like "i d f"
      |> String.replace(" ", "%")

    query = "%#{query}%"

    records =
      DB.Autocomplete
      |> where([p], fragment("indexed_name ilike unaccent(?)", ^query))
      |> order_by(asc: fragment("CASE type
          when 'feature' then 1
          when 'mode' then 2
          when 'format' then 3
          when 'offer' then 4
          when 'region' then 5
          when 'departement' then 6
          when 'epci' then 7
          when 'dataset' then 8
          else 9 END"))
      |> order_by(desc: fragment("similarity(indexed_name, unaccent(?))", ^query))
      |> limit(10)
      |> DB.Repo.all()
      |> case do
        [] -> approx_search_query(query)
        r -> r
      end

    results =
      Enum.map(records, fn res ->
        name =
          case res.type do
            "commune" -> "#{res.nom} (#{res.place_id})"
            _ -> res.nom
          end

        %{name: name, type: res.type, url: get_result_url(conn, res)}
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
      description: "Given a search input, return potentially corresponding results with the associated search URL",
      operationId: "API.DatasetController.datasets_autocomplete",
      parameters: [Operation.parameter(:q, :query, :string, "query")],
      responses: %{
        200 => Operation.response("Dataset", "application/json", TransportWeb.API.Schemas.AutocompleteResponse)
      }
    }
  end
end
