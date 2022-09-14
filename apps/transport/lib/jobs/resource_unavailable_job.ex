defmodule Transport.Jobs.ResourcesUnavailableDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `ResourceUnavailableJob`
  """
  use Oban.Worker, max_attempts: 3
  require Logger
  import Ecto.Query
  alias DB.{Dataset, Repo, Resource, ResourceUnavailability}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    resource_ids = resources_to_check(Map.get(args, "only_unavailable", false))

    Logger.debug("Dispatching #{Enum.count(resource_ids)} ResourceUnavailableJob jobs")

    resource_ids
    |> Enum.map(fn resource_id ->
      %{resource_id: resource_id} |> Transport.Jobs.ResourceUnavailableJob.new()
    end)
    |> Oban.insert_all()

    :ok
  end

  def resources_to_check(false = _only_unavailable) do
    Resource
    |> join(:inner, [r], d in Dataset, on: r.dataset_id == d.id and d.is_active)
    |> where([r], not r.is_community_resource)
    |> where([r], like(r.url, "http%"))
    |> select([r], r.id)
    |> Repo.all()
  end

  def resources_to_check(true = _only_unavailable) do
    ResourceUnavailability
    |> where([r], is_nil(r.end))
    |> select([r], r.resource_id)
    |> Repo.all()
  end
end

defmodule Transport.Jobs.ResourceUnavailableJob do
  @moduledoc """
  Job checking if a resource is available over HTTP or not and
  storing unavailabilities in that case.

  It also updates the relevant resource and keeps up to the following fields:
  - is_available (if the availability of the resource changes)
  - url (if lastest_url points to a new URL)
  """
  use Oban.Worker, max_attempts: 5
  require Logger
  alias DB.{Repo, Resource, ResourceUnavailability}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_id" => resource_id}}) do
    Logger.info("Running ResourceUnavailableJob for #{resource_id}")

    Resource
    |> Repo.get!(resource_id)
    |> update_url()
    |> historize_resource()
    |> check_availability()
    |> update_availability()
  end

  defp check_availability({check_url, %Resource{} = resource}) do
    {Transport.AvailabilityChecker.Wrapper.available?(check_url), resource}
  end

  defp update_url(%Resource{filetype: "file", url: url, latest_url: latest_url} = resource) do
    case follow(latest_url) do
      {:ok, final_url} when final_url != url ->
        resource = resource |> Ecto.Changeset.change(%{url: final_url}) |> Repo.update!()
        {:updated, resource}

      _ ->
        {:noop, resource}
    end
  end

  defp update_url(%Resource{} = resource), do: {:noop, resource}

  defp historize_resource({:noop, resource}), do: {Resource.download_url(resource), resource}

  defp historize_resource({:updated, %Resource{id: resource_id} = resource}) do
    %{resource_id: resource_id} |> Transport.Jobs.ResourceHistoryJob.new() |> Oban.insert!()
    {resource.url, resource}
  end

  defp update_availability({is_available, %Resource{} = resource}) do
    resource |> Resource.changeset(%{is_available: is_available}) |> DB.Repo.update!()
    create_resource_unavailability(is_available, resource)
  end

  def create_resource_unavailability(false = _is_available, %Resource{} = resource) do
    case ResourceUnavailability.ongoing_unavailability(resource) do
      nil ->
        %ResourceUnavailability{resource: resource, start: now()}
        |> Repo.insert!()

        :ok

      %ResourceUnavailability{} ->
        :ok
    end
  end

  def create_resource_unavailability(true = _is_available, %Resource{} = resource) do
    case ResourceUnavailability.ongoing_unavailability(resource) do
      %ResourceUnavailability{} = resource_unavailability ->
        resource_unavailability
        |> Ecto.Changeset.change(%{end: now()})
        |> Repo.update!()

        :ok

      nil ->
        :ok
    end
  end

  @doc """
  Given a URL, follow potential redirections and returns the final URL.

  HTTPoison doesn't give the final URL when following redirects: https://github.com/edgurgel/httpoison/issues/90.

  Inspired from https://github.com/edgurgel/httpoison/issues/90#issuecomment-359951901.
  """
  def follow(url) when is_binary(url), do: follow(url, 5)

  def follow(url, max_redirect) when is_binary(url) and is_integer(max_redirect) and max_redirect > 0 do
    case http_client().get(url) do
      {:ok, %HTTPoison.Response{status_code: status_code, headers: headers}}
      when status_code > 300 and status_code < 400 ->
        case location_header(headers) do
          [url] when is_binary(url) ->
            follow(url, max_redirect - 1)

          _ ->
            {:error, :no_location_header}
        end

      {:ok, %HTTPoison.Response{}} ->
        {:ok, url}

      reason ->
        {:error, reason}
    end
  end

  def follow(url, 0 = _max_redirect) when is_binary(url) do
    {:error, :too_many_redirects}
  end

  defp location_header(headers) do
    for {key, value} <- headers, String.downcase(key) == "location" do
      value
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
