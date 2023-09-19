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

    Enum.each(resource_ids, fn resource_id ->
      %{resource_id: resource_id}
      |> Transport.Jobs.ResourceUnavailableJob.new()
      |> Oban.insert!()
    end)

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
  use Oban.Worker, unique: [period: 60 * 9], max_attempts: 5
  require Logger
  alias DB.{Repo, Resource, ResourceUnavailability}

  # Set this env variable to a list of `resource.id`s (comma separated) to bypass
  # `AvailabilityChecker.available?`. This is *not* something that should be used
  # for too long or for too many resources.
  # Example values: `42,1337`
  # https://github.com/etalab/transport-site/issues/3470
  @bypass_ids_env_name "BYPASS_RESOURCE_AVAILABILITY_RESOURCE_IDS"

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

  defp check_availability({:updated, 200 = _status_code, %Resource{} = resource}) do
    {true, resource}
  end

  defp check_availability({:updated, status_code, %Resource{url: url} = resource})
       when status_code != 200 do
    perform_check(resource, url)
  end

  defp check_availability({:no_op, %Resource{} = resource}) do
    perform_check(resource, Resource.download_url(resource))
  end

  defp perform_check(%Resource{id: resource_id, format: format} = resource, check_url) do
    bypass_resource_ids = @bypass_ids_env_name |> System.get_env("") |> String.split(",")

    if to_string(resource_id) in bypass_resource_ids do
      Logger.info("is_available=true for resource##{resource_id} because the check is bypassed")
      {true, resource}
    else
      {Transport.AvailabilityChecker.Wrapper.available?(format, check_url), resource}
    end
  end

  # GOTCHA: `filetype` is set to `"file"` for exports coming from ODS
  # https://github.com/opendatateam/udata-ods/issues/250
  defp update_url(%Resource{filetype: "file", url: url, latest_url: latest_url} = resource) do
    case follow(latest_url) do
      {:ok, status_code, final_url} when final_url != url ->
        resource = resource |> Ecto.Changeset.change(%{url: final_url}) |> Repo.update!()
        {:updated, status_code, resource}

      _ ->
        {:no_op, resource}
    end
  end

  defp update_url(%Resource{} = resource), do: {:no_op, resource}

  defp historize_resource({:no_op, %Resource{}} = payload), do: payload

  defp historize_resource({:updated, _status_code, %Resource{id: resource_id}} = payload) do
    %{resource_id: resource_id}
    |> Transport.Jobs.ResourceHistoryJob.historize_and_validate_job(history_options: [unique: nil])
    |> Oban.insert!()

    payload
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
