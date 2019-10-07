defmodule TransportWeb.ValidationController do
  use TransportWeb, :controller
  alias DB.{Repo, Validation}
  alias TransportWeb.ResourceController

  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error
  @timeout 60_000

  defp endpoint, do: Application.get_env(:transport, :gtfs_validator_url) <> "/validate"

  def index(%Plug.Conn{} = conn, _) do
    render conn, "index.html"
  end

  def validate(%Plug.Conn{} = conn, %{"upload" => upload_params}) do
    with {:ok, gtfs} <- File.read(upload_params["file"].path),
      {:ok, %@res{status_code: 200, body: body}} <- @client.post(endpoint(), gtfs, recv_timeout: @timeout),
      {:ok, %{"validations" => validations}} <- Poison.decode(body) do
        %Validation{
          date: DateTime.utc_now |> DateTime.to_string,
          details: validations
        }
        |> Repo.insert
      else
        {:error, %@err{reason: error}} -> {:error, error}
        _ -> {:error, "Unknown error"}
      end
      |> case do
        {:ok, %Validation{id: id}} -> redirect(conn, to: validation_path(conn, :show, id))
        _ -> conn
             |> put_flash(:error, dgettext("validations", "Unable to validate file"))
             |> redirect(to: validation_path(conn, :index))
      end
  end

  def show(%Plug.Conn{} = conn, %{} = params) do
    config = make_pagination_config(params)
    validation = Repo.get(Validation, params["id"])

    current_issues = ResourceController.get_issues(validation, params)

    render(conn, "show.html",
    %{validation_id: params["id"],
    other_resources: [],
    issues: Scrivener.paginate(current_issues, config),
    validation_summary: ResourceController.validation_summary(validation)
 })
  end
end
