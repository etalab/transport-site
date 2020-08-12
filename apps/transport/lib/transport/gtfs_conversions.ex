defmodule Transport.GtfsConversions do
  @moduledoc """
  generate a netex and a geojson for each resource that needs it

  This task only send demand for the conversion, the generation in itself will be done by the
  API server asynchronously and posted as community resources on data.gouv.
  """
  alias DB.{Repo, Resource}
  import Ecto.{Changeset, Query}
  require Logger

  @base_url "https://convertisseur.transport.data.gouv.fr"

  @spec convert_all(boolean()) :: any()
  def convert_all(force_update \\ false) do
    Logger.info("generating NeTEx and geojson for all GTFS")

    Resource
    |> filter_convertible_resources()
    |> preload(dataset: [:resources])
    |> Repo.all()
    |> Stream.filter(fn r -> force_update || update_needed?(r) end)
    |> Stream.each(&convert_resource/1)
    |> Stream.run()

    Logger.info("all generation tasks have been launched")
  end

  @spec update_needed?(Resource.t()) :: boolean()
  defp update_needed?(%Resource{conversion_latest_content_hash: nil}) do
    true
  end

  defp update_needed?(%Resource{
         conversion_latest_content_hash: conversion_latest_content_hash,
         content_hash: content_hash
       }) do
    # the resource needs to be converted if the netex have been generated with a different content hash
    conversion_latest_content_hash != content_hash
  end

  @spec convert_resource(Resource.t()) :: {:ok, Ecto.Schema.t()} | {:error, any()}
  defp convert_resource(resource) do
    resource.dataset.resources
    |> Enum.find(fn r -> r.format == "NeTEx" and r.is_community_resource == false end)
    |> case do
      nil ->
        generate_netex_and_geojson(resource)

      _ ->
        # we don't want to generate a netex if there is already one
        generate_geojson(resource)
    end
  end

  def convert_resources_of_dataset(dataset_id) do
    Resource
    |> preload(dataset: [:resources])
    |> where([r], r.dataset_id == ^dataset_id)
    |> filter_convertible_resources()
    |> Repo.all()
    |> case do
      [] ->
        {:error, "no eligible resource"}

      resources ->
        Enum.each(resources, &convert_resource/1)
        {:ok, ""}
    end
  end

  @spec generate_netex_and_geojson(Resource.t()) :: {:ok, Ecto.Schema.t()} | {:error, any()}
  defp generate_netex_and_geojson(resource), do: call_conversion_api(resource, "convert_to_netex_and_geojson")

  @spec generate_geojson(Resource.t()) :: {:ok, Ecto.Schema.t()} | {:error, any()}
  defp generate_geojson(resource), do: call_conversion_api(resource, "gtfs2geojson")

  @spec call_conversion_api(Resource.t(), binary()) :: {:ok, Ecto.Schema.t()} | {:error, any()}
  defp call_conversion_api(resource, endpoint) do
    Logger.info("calling #{endpoint} for #{resource.dataset.title} - #{resource.title} (#{resource.id})")

    url = "#{@base_url}/#{endpoint}?url=#{resource.url}&datagouv_id=#{resource.dataset.datagouv_id}"

    case HTTPoison.get(url) do
      {:ok, %{status_code: 200}} ->
        # Note: we only send a request to convert the GTFS, the generation is done asynchronously
        # the API server will post a communautary resource when available
        Logger.info("conversion ok for #{resource.id}")
        mark_as_converted(resource)

      {:ok, response} ->
        Logger.error("error in call to #{endpoint} for resource #{resource.id}: #{inspect(response)}")
        {:error, response}

      {:error, error} ->
        Logger.error("impossible to call #{endpoint} for resource #{resource.id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @spec mark_as_converted(Resource.t()) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  defp mark_as_converted(resource) do
    # we set the conversion_latest_content_hash to the current resource content hash
    resource
    |> change(conversion_latest_content_hash: resource.content_hash)
    |> Repo.update()
  end

  defp filter_convertible_resources(query) do
    query
    |> where(
      [r],
      not is_nil(r.url) and not is_nil(r.title) and r.format == "GTFS" and r.is_community_resource == false and
        r.is_available
    )
  end
end
