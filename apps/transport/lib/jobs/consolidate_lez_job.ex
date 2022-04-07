defmodule Transport.Jobs.ConsolidateLEZsJob do
  @moduledoc """
  Job in charge of dispatching multiple `GTFSRTEntitiesJob`.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  alias DB.{Dataset, Repo, Resource, ResourceHistory}

  @zfe_schema_name "etalab/schema-zfe"

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
    |> write_files()
  end

  def write_files(consolidated_data) do
    write_file(consolidated_data |> Map.fetch!("aire") |> Jason.encode!(), "aires.json")
    write_file(consolidated_data |> Map.fetch!("voie") |> Jason.encode!(), "voies.json")
  end

  def write_file(content, filename) do
    dst_path = System.tmp_dir!() |> Path.join(filename)
    dst_path |> File.write!(content)
  end

  def type(%Resource{} = resource) do
    if is_voie?(resource), do: "voie", else: "aire"
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
      r.schema_name == @zfe_schema_name and r.is_available and
        fragment("(metadata->'validation'->>'has_errors')::bool = false")
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
