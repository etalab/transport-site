defmodule TransportWeb.BackofficeController do
  use TransportWeb, :controller
  alias Transport.{ImportDataService, ReusableData}
  require Logger

  defp region_names() do
    :mongo
    |> Mongo.find("regions", %{}, pool:  DBConnection.Poolboy)
    |> Enum.map(fn r -> r["properties"]["NOM_REG"] end)
  end

  def index(%Plug.Conn{} = conn, _params) do
    conn
    |> assign(:regions, region_names())
    |> assign(:datasets, ReusableData.list_datasets)
    |> render("index.html")
  end

  defp insert_into_mongo(%{} = dataset) do
    case Mongo.insert_one(:mongo, "datasets", dataset, pool: DBConnection.Poolboy) do
      {:ok, %Mongo.InsertOneResult{inserted_id: mongo_id}} ->
        {:ok, %{"_id" => mongo_id, "id" => dataset["id"]}}
      error ->
        error
    end
  end

  defp import_data({:ok, ids}) do
    ImportDataService.call(ids)
  end
  defp import_data(error), do: error

  defp flash({:ok, _message}, conn) do
    put_flash(conn, :info, dgettext("backoffice", "Dataset added with success"))
  end

  defp flash({:error, message}, conn) do
    put_flash(conn, :error, dgettext("backoffice", "Dataset not added") <> "(" <> message <> ")")
  end

  def new_dataset(%Plug.Conn{} = conn, params) do
    params
    |> Map.take(["spatial", "id", "commune_principale", "region"])
    |> insert_into_mongo
    |> import_data
    |> flash(conn)
    |> index(%{})
  end

end
