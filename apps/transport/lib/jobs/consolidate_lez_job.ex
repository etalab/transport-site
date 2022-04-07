defmodule Transport.Jobs.ConsolidateLEZsJob do
  @moduledoc """
  Job in charge of dispatching multiple `GTFSRTEntitiesJob`.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  alias DB.{Dataset, Resource, Repo}

  @zfe_schema_name "etalab/schema-zfe"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    run()
    :ok
  end

  def run() do
    relevant_resources()
    |> Enum.group_by(&type/1)
    |> Enum.into(%{}, fn {type, resources} ->
      {type, consolidate_features(resources)}
    end)
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
      features: resources |> Enum.map(&content_features/1)
    }
  end

  def content_features(%Resource{url: url}) do
    %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(url, [], follow_redirect: true)
    body |> Jason.decode!() |> Map.fetch!("features")
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
