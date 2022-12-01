defmodule Transport.Jobs.ParkingsRelaisToGeoData do
  @moduledoc """
  Job in charge of taking the parking relais stored in the Base nationale des parcs relais and storing the result in the `geo_data` table.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  @impl Oban.Worker
  def perform(%{}) do
    [resource] = relevant_dataset() |> DB.Dataset.official_resources() |> Enum.filter(&(&1.format == "csv"))

    Transport.Jobs.BaseGeoData.import_replace_data(resource, &prepare_data_for_insert/2)

    :ok
  end

  def relevant_dataset do
    transport_publisher_label = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)

    DB.Dataset
    |> preload(:resources)
    |> where(
      [d],
      d.type == "private-parking" and d.organization == ^transport_publisher_label and
        d.custom_title == "Base nationale des parcs relais"
    )
    |> DB.Repo.one!()
  end

  defp pr_count(""), do: 0
  defp pr_count(str), do: String.to_integer(str)

  def prepare_data_for_insert(body, geo_data_import_id) do
    {:ok, stream} = StringIO.open(body)

    stream
    |> IO.binstream(:line)
    |> CSV.decode(separator: ?;, headers: true)
    |> Stream.filter(fn {:ok, line} -> pr_count(line["nb_pr"]) > 0 end)
    |> Stream.map(fn {:ok, m} ->
      %{
        geo_data_import_id: geo_data_import_id,
        geom: %Geo.Point{
          coordinates:
            {m["Xlong"] |> Transport.Jobs.BaseGeoData.parse_coordinate(),
             m["Ylat"] |> Transport.Jobs.BaseGeoData.parse_coordinate()},
          srid: 4326
        },
        payload: m |> Map.drop(["Xlong", "Ylat"])
      }
    end)
  end
end
