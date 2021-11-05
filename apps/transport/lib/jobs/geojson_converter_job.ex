defmodule Transport.GeojsonConverterJob do
  use Oban.Worker, max_attempts: 1

  alias DB.{Repo, Resource}

  # TODO: handle the case where a resource cannot be found

  @impl true
  def perform(%{id: id, args: %{"resource_id" => resource_id}}) do
    IO.inspect("I, worker, start this job.")

    url = Resource |> Repo.get!(resource_id) |> Map.fetch!(:url)

    # TODO how is the tmp folder cleaned (upon completion or after a crash)?
    file_path = System.tmp_dir!() |> Path.join("#{id}_download")

    # TODO stream file to disk
    # TODO verify headers (content-type) and maybe provide alerts to providers!
    %{status: 200, body: body} = Unlock.HTTP.Client.impl().get!(url, [])
    File.write!(file_path, body)

    # TODO add a bit of logging

    {:ok, output} = file_path |> call_geojson_converter()

    output_path =
      System.tmp_dir!()
      |> Path.join("#{id}_output.geojson")

    File.write!(output_path, output)

    IO.inspect("saving result #{output_path}")

    :ok
  end

  def call_geojson_converter(file_path) do
    # TODO: make sure to have a command that we can run on any dev machine (with docker)
    # TODO: make sure to "clear" the ENV before calling a binary
    # TODO: make sure to "change working directory" to a specific working place
    binary_path = Path.join(Application.fetch_env!(:transport, :transport_tools_folder), "gtfs-geojson")

    case Rambo.run(binary_path, ["--input", file_path]) do
      {:ok, %Rambo{out: res}} -> {:ok, res}
      {:error, %Rambo{err: err_msg}} -> {:error, err_msg}
      {:error, _} = r -> r
    end
  end
end
