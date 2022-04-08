defmodule Transport.Jobs.ConsolidateLEZsJob do
  @moduledoc """
  Consolidates a low emission zones' national database
  using valid `etalab/schema-zfe` resources published
  on our platform.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  alias DB.{Dataset, Repo, Resource, ResourceHistory}

  @schema_name "etalab/schema-zfe"
  @datagouv_dataset_id "624ff4b1bbb449a550264040"
  @datagouv_resources_ids %{
    "voies" => "98c6bcdb-1205-4481-8859-f885290763f2",
    "aires" => "3ddd29ee-00dd-40af-bc98-3367adbd0289"
  }

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    run()
    :ok
  end

  def run do
    relevant_resources()
    |> Enum.group_by(&type/1)
    |> Enum.into(%{}, fn {type, resources} ->
      {type, consolidate_features(resources)}
    end)
    |> update_files()
  end

  def update_files(consolidated_data) do
    for type <- ~w(voies aires) do
      filename = "#{type}.geojson"
      path = write_file(consolidated_data |> Map.fetch!(type) |> Jason.encode!(), filename)

      Datagouvfr.Client.Resources.update(%{
        "dataset_id" => @datagouv_dataset_id,
        "resource_id" => Map.fetch!(@datagouv_resources_ids, type),
        "resource_file" => %{path: path, filename: filename}
      })

      File.rm!(path)
    end
  end

  def write_file(content, filename) do
    dst_path = System.tmp_dir!() |> Path.join(filename)
    dst_path |> File.write!(content)
    dst_path
  end

  def type(%Resource{} = resource) do
    if is_voie?(resource), do: "voies", else: "aires"
  end

  def is_voie?(%Resource{url: url}) do
    url |> String.downcase() |> String.contains?("voie")
  end

  def relevant_resources do
    Resource
    |> join(:inner, [r], d in Dataset,
      on:
        r.dataset_id == d.id and d.type == "low-emission-zones" and
          d.organization != "Point d'Accès National transport.data.gouv.fr"
    )
    |> where(
      [r],
      r.schema_name == @schema_name and fragment("(metadata->'validation'->>'has_errors')::bool = false")
    )
    |> Repo.all()
  end

  def consolidate_features(resources) do
    %{
      type: "FeatureCollection",
      features: resources |> Enum.flat_map(&content_features/1)
    }
  end

  def content_features(%Resource{} = resource) do
    # TO DO: enforce `has_errors` to `false`
    %ResourceHistory{payload: %{"permanent_url" => url, "resource_metadata" => %{"validation" => %{"has_errors" => _}}}} =
      latest_resource_history(resource)

    %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(url, [], follow_redirect: true)
    body |> Jason.decode!() |> Map.fetch!("features")
  end

  def latest_resource_history(%Resource{datagouv_id: datagouv_id}) do
    ResourceHistory
    |> where([rh], rh.datagouv_id == ^datagouv_id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one!()
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
