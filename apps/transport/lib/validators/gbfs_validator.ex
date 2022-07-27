defmodule Transport.Validators.GBFSValidator do
  @moduledoc """
  Validate a file against a Table Schema schema using [the Validata API](https://validata.fr).
  """
  # https://github.com/etalab/transport-site/issues/2390
  # Plan to move the other validator here as we deprecate
  # the previous validation flow.
  alias Transport.Cache.API, as: Cache
  alias Transport.Shared.GBFSMetadata.Wrapper, as: GBFSMetadata
  @github_repository "MobilityData/gbfs-validator"
  @behaviour Transport.Validators.Validator

  @impl Transport.Validators.Validator
  def validate_and_save(%DB.Resource{url: url, type: "gbfs", id: resource_id}) do
    result = GBFSMetadata.compute_feed_metadata(url, "https://#{Application.fetch_env!(:transport, :domain_name)}")

    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      command: validator_command(),
      validated_data_name: url,
      validator: validator_name(),
      result: Map.fetch!(result, :validation),
      metadata: Map.reject(result, fn {key, _val} -> key == :validation end),
      resource_id: resource_id,
      validator_version: validator_version()
    }
    |> DB.Repo.insert!()

    :ok
  end

  @impl Transport.Validators.Validator
  def validator_name, do: "validata-api"

  defp validator_command, do: Application.fetch_env!(:transport, :gbfs_validator_url)

  @doc """
  Fetches the latest commit sha from the `gbfs-validator` GitHub repository to known
  the validator version.

  May be solved by https://github.com/MobilityData/gbfs-validator/issues/77 in the future.
  """
  def validator_version do
    get_latest_commit_sha = fn ->
      %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(github_api_url())
      default_branch = Map.fetch!(Jason.decode!(body), "default_branch")

      %HTTPoison.Response{status_code: 200, body: body} =
        http_client().get!("#{github_api_url()}/commits/#{default_branch}")

      Map.fetch!(Jason.decode!(body), "sha")
    end

    Cache.fetch("#{__MODULE__}::validator_version", get_latest_commit_sha, :timer.minutes(5))
  end

  defp github_api_url, do: "https://api.github.com/repos/#{@github_repository}"
  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
