defmodule TransportWeb.API.DatasetController do
  use TransportWeb, :controller
  alias Transport.{Dataset, Helpers, Repo}

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
      "updated" => Helpers.format_date(resource.last_update),
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
