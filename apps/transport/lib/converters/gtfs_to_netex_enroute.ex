defmodule Transport.Converters.GTFSToNeTExEnRoute do
  @moduledoc """
  A client of for the EnRoute's Conversions API.
  Documentation: https://documenter.getpostman.com/view/9203997/SzmfXwrp
  """
  require Logger
  @base_url "https://chouette-convert.enroute.mobi/api/conversions"

  @doc """
  Creates a GTFS to NeTEx conversion job on the EnRoute's API.
  Returns the job UUID as a string.
  """
  @spec create_gtfs_to_netex_conversion(binary(), binary()) :: binary()
  def create_gtfs_to_netex_conversion(filepath, profile \\ "french") do
    Logger.info("Converting #{filepath} from GTFS to NeTEx with the #{profile} profile")

    form =
      {:multipart,
       [
         {"type", "gtfs-netex"},
         {"options[profile]", profile},
         {:file, filepath, {"form-data", [{:name, "file"}, {:filename, Path.basename(filepath)}]}, []}
       ]}

    %HTTPoison.Response{status_code: 201, body: body} = http_client().post!(base_url(), form, auth_headers())
    body |> Jason.decode!() |> Map.fetch!("id")
  end

  @doc """
  Polls the API to know if the conversion is finished.
  """
  @spec get_conversion(binary()) :: :error | {:success | :pending | :failed, map()}
  def get_conversion(uuid) do
    case http_client().get(Path.join(base_url(), uuid), auth_headers()) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        json = Jason.decode!(body)

        case Map.fetch!(json, "status") do
          "success" ->
            Logger.info("Conversion ##{uuid} is finished. #{inspect(json)}")
            {:success, json}

          value when value in ["pending", "running"] ->
            Logger.info("Conversion ##{uuid} is #{value}. #{inspect(json)}")
            {:pending, json}

          "failed" ->
            {:failed, json}
        end

      error ->
        Logger.error("Conversion ##{uuid} has an error. #{inspect(error)}")
        :error
    end
  end

  @doc """
  Downloads the conversion and save it to the local disk using a file stream.
  """
  @spec download_conversion(binary(), File.Stream.t()) :: :ok
  def download_conversion(uuid, %File.Stream{path: path} = file_stream) do
    url = Path.join([base_url(), uuid, "download"])
    Logger.info("Downloading conversion ##{uuid} to file stream at #{path}")

    Req.get!(url, compressed: false, headers: auth_headers(), into: file_stream)
    :ok
  end

  defp base_url() do
    # Use Bypass with Req in the test environment, we need to change the base URL
    bypass = Process.get(:req_bypass)

    if Mix.env() == :test and not is_nil(bypass) do
      "http://localhost:#{bypass.port}"
    else
      @base_url
    end
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()

  defp auth_headers do
    [{"authorization", "Token token=#{Application.fetch_env!(:transport, :enroute_token)}"}]
  end
end
