defmodule Transport.Validators.GBFSValidator do
  @moduledoc """
  Validate and extract metadata for GBFS feed using [the MobilityData GBFS validator](https://gbfs-validator.netlify.app) and our own metadata extractor.
  """
  # https://github.com/etalab/transport-site/issues/2390
  # Plan to move the other validator here as we deprecate
  # the previous validation flow.
  alias Transport.Shared.GBFSMetadata.Wrapper, as: GBFSMetadata
  @github_repository "MobilityData/gbfs-validator"
  @behaviour Transport.Validators.Validator

  @impl Transport.Validators.Validator
  def validate_and_save(%DB.Resource{url: url, format: "gbfs", id: resource_id}) do
    result = GBFSMetadata.compute_feed_metadata(url, "https://#{Application.fetch_env!(:transport, :domain_name)}")

    {validator_version, validation_result} = result |> Map.fetch!(:validation) |> Map.pop!(:validator_version)

    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      command: validator_command(),
      validated_data_name: url,
      validator: validator_name(),
      result: Map.from_struct(validation_result),
      metadata: %DB.ResourceMetadata{
        metadata: Map.reject(result, fn {key, _val} -> key == :validation end),
        resource_id: resource_id
      },
      resource_id: resource_id,
      validator_version: validator_version
    }
    |> DB.Repo.insert!()

    :ok
  end

  @impl Transport.Validators.Validator
  def validator_name, do: @github_repository

  defp validator_command, do: Application.fetch_env!(:transport, :gbfs_validator_url)
end
