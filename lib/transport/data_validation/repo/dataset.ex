defmodule Transport.DataValidation.Repo.Dataset do
  @moduledoc """
  A repository to validate datasets.
  """

  @behaviour Transport.DataValidation.Repo

  alias Transport.DataValidation.Aggregates.Dataset
  alias Transport.DataValidation.Queries.FindDataset
  alias Transport.DataValidation.Commands.CreateDataset
  alias Transport.DataValidation.Commands.ValidateDataset

  # mongodb
  @pool DBConnection.Poolboy

  # gtfs validator
  @endpoint Application.get_env(:transport, :gtfs_validator_url) <> "/validate"
  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error
  @timeout 50_000

  @doc """
  Finds a dataset.
  """
  @spec execute(FindDataset.t()) :: {:ok, nil} | {:ok, Dataset.t()} | {:error, any}
  def execute(%FindDataset{} = query) do
    :mongo
    |> Mongo.find_one("datasets", Map.from_struct(query), pool: @pool)
    |> case do
      {:error, error} ->
        {:error, error}

      nil ->
        {:ok, nil}

      result ->
        uuid =
          result
          |> Map.get("_id")
          |> BSON.ObjectId.encode!()

        dataset =
          result
          |> Dataset.new()
          |> Map.put(:uuid, uuid)

        {:ok, dataset}
    end
  end

  @doc """
  Creates a dataset.
  """
  @spec execute(CreateDataset.t()) :: {:ok, Dataset.t()} | {:error, any}
  def execute(%CreateDataset{} = command) do
    :mongo
    |> Mongo.insert_one("datasets", Map.from_struct(command), pool: @pool)
    |> case do
      {:error, error} ->
        {:error, error}

      {:ok, _} ->
        command
        |> FindDataset.new()
        |> execute
    end
  end

  @doc """
  Validates a dataset by url.
  """
  @spec execute(ValidateDataset.t()) :: {:ok, [Dataset.Validation.t()]} | {:error, any()}
  def execute(%ValidateDataset{download_url: url}) when is_binary(url) do
    with {:ok, %@res{status_code: 200, body: body}} <-
           @client.get(@endpoint <> "?url=#{url}", [], timeout: @timeout, recv_timeout: @timeout),
         {:ok, validations} <- Poison.decode(body, as: [%Dataset.Validation{}]) do
      {:ok, validations}
    else
      {:error, %@err{reason: error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end
end
