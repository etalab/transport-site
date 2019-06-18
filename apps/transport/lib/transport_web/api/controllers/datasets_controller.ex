defmodule TransportWeb.API.DatasetController do
  use TransportWeb, :controller
  alias OpenApiSpex.Operation
  alias Transport.{Dataset, Helpers, Repo}
  alias TransportWeb.API.Schemas.DatasetsResponse

  @spec open_api_operation(any) :: Operation.t
  def open_api_operation(action), do: apply(__MODULE__, :"#{action}_operation", [])

  @spec datasets_operation() :: Operation.t
  def datasets_operation do
    %Operation{
      tags: ["datasets"],
      summary: "Show datasets and its resources",
      description: "For every dataset, show its associated resources, url and validity date",
      operationId: "API.DatasetController.datasets",
      parameters: [],
      responses: %{
        200 => Operation.response("Dataset", "application/json", DatasetsResponse)
      }
    }
  end

  def datasets(%Plug.Conn{} = conn, _params) do
    data =
      %{"type" => "public-transit"}
      |> Dataset.list_datasets()
      |> Repo.all
      |> Repo.preload([:resources, :aom])
      |> Enum.map(&transform_dataset/1)
    render(conn, %{data: data})
  end

  defp transform_dataset(dataset) do
    %{
      "datagouv_id" => dataset.datagouv_id,
      "title" => dataset.spatial,
      "created_at" => dataset.created_at,
      "updated" => Helpers.last_updated(dataset.resources),
      "resources" => Enum.map(dataset.resources, &transform_resource/1),
      "aom" => transform_aom(dataset.aom)
    }
  end

  defp transform_resource(resource) do
    %{
      "title" => resource.title,
      "updated" => Helpers.format_datetime(resource.last_update),
      "url" => resource.latest_url,
      "end_calendar_validity" => resource.metadata["end_date"]
    }
  end

  defp transform_aom(nil), do: %{"name" => nil}
  defp transform_aom(aom) do
    %{
      "name" => aom.nom
    }
  end
end
