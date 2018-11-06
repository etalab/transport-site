defmodule TransportWeb.BackofficeController do
  use TransportWeb, :controller
  alias Transport.{ImportDataService, ReusableData}
  require Logger

  defp region_names do
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

  defp insert_into_mongo(%{"id" => id} = dataset) do
    case Mongo.insert_one(:mongo, "datasets", dataset, pool: DBConnection.Poolboy) do
      {:ok, %Mongo.InsertOneResult{inserted_id: mongo_id}} ->
        {:ok, %{"_id" => mongo_id, "id" => id}}
      error ->
        error
    end
  end

  defp import_data({:ok, ids}) do
    ImportDataService.call(ids)
  end
  defp import_data(error), do: error

  defp flash({:ok, _message}, conn, ok_message, _err_message) do
    put_flash(conn, :info, ok_message)
  end

  defp flash({:error, message}, conn, _ok_message, err_message) do
    put_flash(conn, :error, "#{err_message} (#{message})")
  end

  def new_dataset(%Plug.Conn{} = conn, params) do
    params
    |> Map.take(["spatial", "id", "commune_principale", "region"])
    |> insert_into_mongo
    |> import_data
    |> flash(conn, dgettext("backoffice", "Dataset added with success"), dgettext("backoffice", "Could not add dataset"))
    |> index(%{})
  end

  def import_from_data_gouv_fr(%Plug.Conn{} = conn, %{"id" => id}) do
    :mongo
    |> Mongo.find("datasets", %{"id" => id}, pool:  DBConnection.Poolboy)
    |> Enum.map(fn dataset -> import_data({:ok, dataset}) end)
    |> Enum.reduce(conn, fn(result, c) -> flash(result, c,
            dgettext("backoffice", "Dataset imported with success"),
            dgettext("backoffice", "Dataset not imported"))
      end)
    |> index(%{})
  end

  def delete(%Plug.Conn{} = conn, %{"id" => id}) do
    :mongo
    |> Mongo.delete_one("datasets", %{"id" => id}, pool:  DBConnection.Poolboy)
    |> flash(conn, dgettext("backoffice", "Dataset deleted"), dgettext("backoffice", "Could not delete dataset"))
    |> index(%{})
  end

end
