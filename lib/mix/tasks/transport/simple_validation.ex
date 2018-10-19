defmodule Mix.Tasks.Transport.SimpleValidation do
  @moduledoc """
  Passes a dataset’s url to the validator and stores the validation results in the database
  """

  use Mix.Task
  require Logger

  @endpoint Application.get_env(:transport, :gtfs_validator_url) <> "/validate"
  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error
  @timeout 60_000

  def run(_) do
    Mix.Task.run("app.start", [])
    :mongo
    |> Mongo.find("datasets",
                  %{"download_url" => %{"$ne" => nil}},
                  pool: DBConnection.Poolboy)
    |> Enum.each(&validate_and_save/1)
  end

  def validate_and_save(dataset) do
    Logger.info("Validating " <> dataset["download_url"] )
    case dataset |> validate |> save_validations do
      {:ok, _} -> Logger.info("Ok!")
      {:error, error} -> Logger.warn("Error: " <> error)
      _ -> Logger.warn("Unknown error")
    end
  end

  def validate(%{"download_url" => url}) do
    with {:ok, %@res{status_code: 200, body: body}} <-
           @client.get(@endpoint <> "?url=#{url}", [], timeout: @timeout, recv_timeout: @timeout),
         {:ok, validations} <- Poison.decode(body) do
      {:ok, %{url: url, validations: validations}}
    else
      {:ok, %@res{body: body}} -> {:error, body}
      {:error, %@err{reason: error}} -> {:error, error}
      {:error, error} -> {:error, error}
      _ -> {:error, "Unknown error"}
    end
  end

  def save_validations({:ok, %{url: url, validations: validations}}) do
    Mongo.find_one_and_update(:mongo,
                              "datasets",
                              %{"download_url" => url},
                              %{"$set" => validations},
                              pool: DBConnection.Poolboy)
  end
  def save_validations({:error, error}), do: error
  def save_validations(error), do: {:error, error}
end
