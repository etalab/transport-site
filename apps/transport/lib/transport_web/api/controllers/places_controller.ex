defmodule TransportWeb.API.PlacesController do
  use TransportWeb, :controller
  alias DB.Repo
  alias Ecto.Adapters.SQL
  alias Helpers
  alias OpenApiSpex.Operation
  alias TransportWeb.API.Schemas.{AutocompleteResponse}

  @spec open_api_operation(any) :: Operation.t()
  def open_api_operation(action), do: apply(__MODULE__, :"#{action}_operation", [])

  @spec get_result_url(Plug.Conn.t(), %{binary() => binary()}) :: binary()
  def get_result_url(conn, %{"id" => id, "type" => "commune"}), do: dataset_path(conn, :by_commune_insee, id)

  def get_result_url(conn, %{"id" => id, "type" => "region"}), do: dataset_path(conn, :by_region, id)

  def get_result_url(conn, %{"id" => id, "type" => "aom"}), do: dataset_path(conn, :by_aom, id)

  @spec autocomplete(Plug.Conn.t(), map) :: Plug.Conn.t()
  def autocomplete(%Plug.Conn{} = conn, %{"q" => query}) do
    commune =
      SQL.query!(
        Repo,
        "
        SELECT nom, id, type FROM
        (
          (
            SELECT c.nom AS nom, c.insee AS id, 'commune' AS type
            FROM commune c WHERE unaccent(nom) ilike '%' || unaccent($1) || '%'
            ORDER BY levenshtein(unaccent(c.nom), unaccent($1))
            limit 10
          )
          UNION
          (
            SELECT r.nom AS nom, CAST(r.id AS varchar) AS id, 'region' AS type
            FROM region r WHERE unaccent(r.nom) ilike '%' || unaccent($1) || '%'
            ORDER BY levenshtein(unaccent(r.nom), unaccent($1))
            limit 3
          )
          UNION
          (
            SELECT a.nom AS nom, CAST(a.id AS varchar) AS id, 'aom' AS type
            FROM aom a WHERE unaccent(a.nom) ilike '%' || unaccent($1) || '%'
            ORDER BY levenshtein(unaccent(a.nom), unaccent($1))
            limit 5
          )
        ) AS results
        ORDER BY levenshtein(unaccent(nom), unaccent($1))
        LIMIT 10
        ",
        [query]
      )

    results =
      commune.rows
      |> Enum.map(fn res -> commune.columns |> Enum.zip(res) |> Enum.into(%{}) end)
      |> Enum.map(fn res -> %{name: res["nom"], type: res["type"], url: get_result_url(conn, res)} end)

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
