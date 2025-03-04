defmodule Transport.Jobs.ConsolidateLEZsJob do
  @moduledoc """
  Consolidates a low emission zones' national database
  using valid `etalab/schema-zfe` resources published
  on our platform.

  Preferred way to run for now (until we have more safeguards!):
  - in iex, run `consolidate()`, look at logs and inspect the files
  - run the Oban job to consolidate and update files on data.gouv.fr
  """
  use Oban.Worker, max_attempts: 3
  require Logger
  import Ecto.Query
  alias DB.{AOM, Dataset, MultiValidation, Repo, Resource, ResourceHistory}
  alias Transport.CSVDocuments

  @schema_name "etalab/schema-zfe"
  @lez_dataset_type "low-emission-zones"

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    consolidate() |> update_files()
    Oban.Notifier.notify(Oban, :gossip, %{complete: job_id})
    :ok
  end

  def consolidate do
    relevant_resources()
    |> Enum.group_by(&type/1)
    |> Enum.map(fn {type, resources} ->
      details = resources |> Enum.map_join(", ", &"#{&1.dataset.custom_title} (#{&1.title})")
      Logger.info("Found #{Enum.count(resources)} resources for #{type}: #{details}")
      {type, consolidate_features(resources)}
    end)
  end

  def update_files(consolidated_data) do
    consolidated_data
    |> Enum.each(fn {type, data} ->
      filename = "#{type}.geojson"
      filepath = tmp_filepath(filename)

      try do
        write_file(filepath, data |> Jason.encode!())

        Datagouvfr.Client.Resources.update(%{
          "dataset_id" => Map.fetch!(consolidation_configuration(), :dataset_id),
          "resource_id" => resource_id_for_type(type),
          "resource_file" => %{path: filepath, filename: filename}
        })

        Logger.info("Updated #{filename} on data.gouv.fr")
      after
        File.rm(filepath)
      end
    end)
  end

  def write_file(filepath, content) do
    Logger.info("Created #{filepath}")
    filepath |> File.write!(content)
  end

  def tmp_filepath(filename) when filename in ["aires.geojson", "voies.geojson"],
    do: Path.join(System.tmp_dir!(), filename)

  def type(%Resource{dataset: %Dataset{type: @lez_dataset_type}} = resource) do
    if voie?(resource), do: "voies", else: "aires"
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
  def voie?(%Resource{url: url, dataset: %Dataset{type: @lez_dataset_type}}) do
    url |> String.downcase() |> String.contains?("voie")
  end

  def relevant_resources do
    own_publisher = pan_publisher()

    Resource
    |> join(:inner, [r], d in Dataset,
      on:
        r.dataset_id == d.id and d.type == @lez_dataset_type and
          d.organization_id != ^own_publisher
    )
    |> where([r], r.schema_name == @schema_name)
    |> preload(dataset: [:aom])
    |> Repo.all()
  end

  def consolidate_features(resources) do
    %{
      type: "FeatureCollection",
      features:
        resources
        |> Enum.map(fn %Resource{} = resource -> {resource, latest_valid_resource_history(resource)} end)
        # Do not consolidate resources without a valid resource history
        |> Enum.reject(fn {_, resource_history} -> is_nil(resource_history) end)
        |> Enum.flat_map(&content_features/1)
    }
  end

  defp content_features({%Resource{} = resource, %ResourceHistory{payload: %{"permanent_url" => url}}}) do
    %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(url, [], follow_redirect: true)

    body
    |> Jason.decode!()
    |> Map.fetch!("features")
    |> Enum.map(&add_publisher(&1, publisher_details(resource)))
  end

  defp latest_valid_resource_history(%Resource{id: resource_id}) do
    ResourceHistory
    |> join(:inner, [rh], mv in MultiValidation,
      on: mv.resource_history_id == rh.id and fragment("(result->>'has_errors')::bool = false")
    )
    |> where([rh, _mv], rh.resource_id == ^resource_id)
    |> order_by([rh, _mv], desc: :inserted_at)
    |> limit(1)
    |> select([rh, _mv], rh)
    |> Repo.one()
  end

  defp add_publisher(features, publisher_details) do
    Map.put(features, "publisher", publisher_details)
  end

  def publisher_details(%Resource{dataset: %Dataset{aom: %AOM{} = aom}}) do
    %{
      "nom" => aom.nom,
      "siren" => aom.siren,
      "forme_juridique" => aom.forme_juridique,
      "zfe_id" => zfe_id(aom.siren)
    }
  end

  @doc """
  iex> publisher_details(%DB.Resource{dataset: %DB.Dataset{organization: "Dijon metropole"}})
  %{"forme_juridique" => "Métropole", "nom" => "Dijon Métropole", "siren" => "242100410", "zfe_id" => "DIJON"}
  """
  def publisher_details(%Resource{dataset: %Dataset{organization: organization}}) do
    CSVDocuments.zfe_ids()
    |> Enum.find_value(
      &if lower_unaccent(organization) == lower_unaccent(&1["epci_principal"]),
        do: %{
          "nom" => &1["epci_principal"],
          "siren" => &1["siren"],
          "forme_juridique" => &1["forme_juridique"],
          "zfe_id" => zfe_id(&1["siren"])
        }
    )
  end

  def zfe_id(siren) do
    zfe_id =
      CSVDocuments.zfe_ids()
      |> Enum.find_value(&if siren == &1["siren"] or String.contains?(&1["autres_siren"], siren), do: &1["code"])

    if is_nil(zfe_id) do
      Logger.error("Could not find zfe_id for SIREN #{siren}")
    end

    zfe_id
  end

  def pan_publisher do
    Application.fetch_env!(:transport, :datagouvfr_transport_publisher_id)
  end

  def resource_id_for_type(type) do
    consolidation_configuration() |> Map.fetch!(:resource_ids) |> Map.fetch!(type)
  end

  def consolidation_configuration do
    Map.fetch!(Application.fetch_env!(:transport, :consolidation), :zfe)
  end

  @doc """
  Replaces accented letters by their regular versions and lowercase.

  iex> lower_unaccent("Et Ça sera sa moitié.")
  "et ca sera sa moitie."
  """
  def lower_unaccent(value) when is_binary(value) do
    value |> String.downcase() |> unaccent()
  end

  @doc """
  Replaces accented letters by their regular versions.
  Taken from https://stackoverflow.com/a/68724296

  iex> unaccent("Et Ça sera sa moitié.")
  "Et Ca sera sa moitie."
  """
  @spec unaccent(binary()) :: binary()
  def unaccent(value) when is_binary(value) do
    ~r/\p{Mn}/u
    |> Regex.replace(value |> :unicode.characters_to_nfd_binary(), "")
    |> :unicode.characters_to_nfc_binary()
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
