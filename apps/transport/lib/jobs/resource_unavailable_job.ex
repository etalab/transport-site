defmodule Transport.Jobs.ResourcesUnavailableDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `ResourceUnavailableJob`
  """
  use Oban.Worker, max_attempts: 3
  require Logger
  import Ecto.Query
  alias DB.{Repo, Resource, ResourceUnavailability}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    resource_ids = resources_to_check(Map.get(args, "only_unavailable", false))

    Logger.debug("Dispatching #{Enum.count(resource_ids)} ResourceUnavailableJob jobs")

    Enum.each(resource_ids, fn resource_id ->
      %{resource_id: resource_id}
      |> Transport.Jobs.ResourceUnavailableJob.new()
      |> Oban.insert!()
    end)

    :ok
  end

  def resources_to_check(false = _only_unavailable) do
    DB.Dataset.base_with_hidden_datasets()
    |> DB.Resource.join_dataset_with_resource()
    |> where([resource: r], not r.is_community_resource and like(r.url, "http%"))
    |> select([resource: r], r.id)
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
  This job:
  - Updates the URL if needed by following the latest_url for files stored on data.gouv.fr
  - For all resources, check whether a resource is available over HTTP. If not: it creates an unavailability in the database
  - Updates is_available if the availability of the resource has changed
  """
  use Oban.Worker, unique: [period: {9, :minutes}], max_attempts: 5
  require Logger
  alias DB.{Repo, Resource, ResourceUnavailability}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_id" => resource_id}}) do
    Logger.info("Running ResourceUnavailableJob for #{resource_id}")

    Resource
    |> Repo.get!(resource_id)
    |> DB.Repo.preload(:dataset)
    |> maybe_update_url()
    |> historize_resource()
    |> check_availability()
    |> update_resource()
    |> create_or_update_resource_unavailability()
  end

  # We only update url for filetype : "file" = hosted on data.gouv.fr
  defp maybe_update_url(%Resource{filetype: "file", url: url, latest_url: latest_url} = resource) do
    case follow(latest_url) do
      {:ok, 200 = _status_code, final_url} when final_url != url ->
        resource = resource |> Ecto.Changeset.change(%{url: final_url}) |> Repo.update!()
        {:updated, resource}

      _ ->
        {:no_op, resource}
    end
  end

  defp maybe_update_url(%Resource{} = resource), do: {:no_op, resource}

  defp historize_resource({:no_op, %Resource{}} = payload), do: payload

  defp historize_resource({:updated, %Resource{id: resource_id}} = payload) do
    %{resource_id: resource_id}
    |> Transport.Jobs.ResourceHistoryJob.historize_and_validate_job(history_options: [unique: nil])
    |> Oban.insert!()

    payload
  end

  # We've just updated the URL by following it until we got a 200, so it's available
  defp check_availability({:updated, %Resource{} = resource}) do
    {true, resource}
  end

  defp check_availability({:no_op, %Resource{id: resource_id, format: format} = resource}) do
    if resource_id in skip_resource_ids() do
      {true, resource}
    else
      download_url = Resource.download_url(resource)
      is_available = Transport.AvailabilityChecker.Wrapper.available?(format, download_url)
      {is_available, resource}
    end
  end

  @doc """
  Returns the list of resource IDs that should always be considered as available.
  """
  def skip_resource_ids do
    Application.fetch_env!(:transport, :resource_unavailable_skip_resource_ids)
  end

  defp update_resource({is_available, %Resource{} = resource}) do
    resource = resource |> Resource.changeset(%{is_available: is_available}) |> DB.Repo.update!()
    {is_available, resource}
  end

  def create_or_update_resource_unavailability({false = _is_available, %Resource{} = resource}) do
    case ResourceUnavailability.ongoing_unavailability(resource) do
      nil ->
        %ResourceUnavailability{resource: resource, start: now()}
        |> Repo.insert!()

        :ok

      %ResourceUnavailability{} ->
        :ok
    end
  end

  def create_or_update_resource_unavailability({true = _is_available, %Resource{} = resource}) do
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
        case Transport.Http.Utils.location_header(headers) do
          [url] when is_binary(url) ->
            follow(url, max_redirect - 1)

          _ ->
            {:error, :no_location_header}
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:ok, status_code, url}

      reason ->
        {:error, reason}
    end
  end

  def follow(url, 0 = _max_redirect) when is_binary(url) do
    {:error, :too_many_redirects}
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
