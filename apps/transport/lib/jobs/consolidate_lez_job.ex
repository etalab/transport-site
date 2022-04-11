defmodule Transport.Jobs.ConsolidateLEZsJob do
  @moduledoc """
  Consolidates a low emission zones' national database
  using valid `etalab/schema-zfe` resources published
  on our platform.
  """
  use Oban.Worker, max_attempts: 3
  require Logger
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
    consolidate() |> update_files()
    :ok
  end

  def consolidate do
    relevant_resources()
    |> Enum.group_by(&type/1)
    |> Enum.map(fn {type, resources} ->
      details = resources |> Enum.map_join(&"#{&1.dataset.custom_title} (#{&1.title})", ", ")
      Logger.info("Found #{Enum.count(resources)} resources for #{type}: #{details}")
      {type, consolidate_features(resources)}
    end)
  end

  def update_files(consolidated_data) do
    consolidated_data
    |> Enum.each(fn {type, data} ->
      filename = "#{type}.geojson"
      path = write_file(filename, data |> Jason.encode!())

      Datagouvfr.Client.Resources.update(%{
        "dataset_id" => @datagouv_dataset_id,
        "resource_id" => Map.fetch!(@datagouv_resources_ids, type),
        "resource_file" => %{path: path, filename: filename}
      })

      Logger.info("Updated #{filename} on data.gouv.fr")

      File.rm!(path)
    end)
  end

  def write_file(filename, content) do
    dst_path = System.tmp_dir!() |> Path.join(filename)
    Logger.info("Created #{dst_path}")
    dst_path |> File.write!(content)
    dst_path
  end

  def type(%Resource{dataset: %Dataset{type: "low-emission-zones"}} = resource) do
    if is_voie?(resource), do: "voies", else: "aires"
  end

  @doc """
  ZFE files can be of 2 types:
  - `aires` is a perimeter
  - `voies` describes roads where rules may be different than what's described in a perimeter. They act as a kind of override.

  The [schema](https://schema.data.gouv.fr/etalab/schema-zfe/) advises to name files according to their type

  > Nous préconisons aux producteurs de données de publier leurs fichiers concernant les zones avec la règle de nommage suivante : zfe_zone_nom.geojson avec nom étant le nom de la collectivité productrice des données, par exemple zfe_zone_grenoble.geojson. Pour les fichiers concernant les voies spéciales : zfe_voie_speciale_nom.geojson, avec nom étant le nom de la collectivité productrice des données, par exemple zfe_voie_speciale_grenoble.geojson.

  Unfortunately this is not followed by everyone so we cannot be strict about it.

  The current logic looks for the keyword `voie` in the URL/filename.
  We could also inspect the GeoJSON payload and look for `MultiLineString`|`MultiLine`
  """
  def is_voie?(%Resource{url: url, dataset: %Dataset{type: "low-emission-zones"}}) do
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
    |> preload(:dataset)
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
