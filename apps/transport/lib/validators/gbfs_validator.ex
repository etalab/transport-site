defmodule Transport.Validators.GBFSValidator do
  @moduledoc """
  Validate and extract metadata for GBFS feed using [the MobilityData GBFS validator](https://gbfs-validator.netlify.app) and our own metadata extractor.
  """
  @github_repository "MobilityData/gbfs-validator"
  @behaviour Transport.Validators.Validator

  @impl Transport.Validators.Validator
  def validate_and_save(%DB.Resource{url: url, format: "gbfs", id: resource_id}) do
    result = Transport.GBFSMetadata.Wrapper.compute_feed_metadata(url)

    {validator_version, validation_result} = result |> Map.fetch!(:validation) |> Map.pop!(:validator_version)

    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      command: validator_command(),
      validated_data_name: url,
      validator: validator_name(),
      result: Map.from_struct(validation_result),
      digest: Map.from_struct(validation_result) |> Map.new(fn {k, v} -> {to_string(k), v} end) |> digest(),
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

  @doc """
  iex> digest(%{"warnings_count" => 2, "errors_count" => 3, "issues" => []})
  %{"errors_count" => 3, "warnings_count" => 2}
  iex> digest(%{"issues" => []})
  %{}
  """
  @spec digest(map) :: map
  def digest(%{} = validation_result) do
    Map.intersect(%{"warnings_count" => 0, "errors_count" => 0}, validation_result)
  end
end
