defmodule Transport.DataValidation.Repo.Dataset do
  @moduledoc """
  A repository to validate datasets.
  """

  alias BSON.ObjectId
  alias Transport.DataValidation.Aggregates.{Dataset, Dataset.Validation}
  alias Transport.DataValidation.Queries.FindDataset
  alias Transport.DataValidation.Events.{DatasetCreated, DatasetValidated}

  # mongodb
  @pool DBConnection.Poolboy

  # gtfs validator
  @endpoint Application.get_env(:transport, :gtfs_validator_url) <> "/validate"
  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error
  @timeout 60_000

  @doc """
  Finds a dataset.
  """
  @spec read(FindDataset.t()) :: {:ok, nil} | {:ok, Dataset.t()} | {:error, any}
  def read(%FindDataset{} = query) do
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
          |> ObjectId.encode!()

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
  @spec project(DatasetCreated.t()) :: {:ok, Dataset.t()} | {:error, any}
  def project(%DatasetCreated{} = event) do
    :mongo
    |> Mongo.insert_one("datasets", Map.from_struct(event), pool: @pool)
    |> case do
      {:error, error} ->
        {:error, error}

      {:ok, _} ->
        event
        |> FindDataset.new()
        |> read
    end
  end

  @doc """
  Validates a dataset by url.
  """
  @spec project(DatasetValidated.t()) :: {:ok, [Validation.t()]} | {:error, any()}
  def project(%DatasetValidated{download_url: url}) when is_binary(url) do
    with {:ok, %@res{status_code: 200, body: body}} <-
           @client.get(@endpoint <> "?url=#{url}", [], timeout: @timeout, recv_timeout: @timeout),
         {:ok, validations} <- Poison.decode(body, as: [%Validation{}]) do
      {:ok, validations}
    else
      {:ok, %@res{status_code: 500, body: body}} ->
        {:error,
         body
         |> Poison.decode!()
         |> Map.get("error")}

      {:error, %@err{reason: error}} ->
        {:error, error}

      {:error, error} ->
        {:error, error}
    end
  end
end
