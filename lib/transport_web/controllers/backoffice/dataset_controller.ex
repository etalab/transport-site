defmodule TransportWeb.Backoffice.DatasetController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.Datasets
  alias Transport.{AOM, Dataset, ImportDataService, Repo, Resource}
  import Ecto.Query

  def new_dataset(%Plug.Conn{} = conn, params) do
    with datagouv_id when not is_nil(datagouv_id)  <- Datasets.get_id_from_url(conn, params["url"]),
         {:ok, aom_id} <- get_aom_id(params),
         {:ok, datagouv_dataset} <- ImportDataService.import_from_udata(datagouv_id, params["type"]),
         params <- Map.put(params, "aom_id", aom_id),
         params <- Map.merge(params, datagouv_dataset),
         changeset <- Dataset.changeset(%Dataset{}, params),
         {:ok, _dataset} <- Repo.insert(changeset)
    do
      conn
      |> put_flash(:info, dgettext("backoffice_dataset", "Dataset added with success"))
    else
      {:error, error} ->
        conn
        |> put_flash(:error, dgettext("backoffice_dataset", "Could not add dataset"))
        |> put_flash(:error, error)
    end
    |> redirect(to: backoffice_page_path(conn, :index))
  end

  def import_from_data_gouv_fr(%Plug.Conn{} = conn, %{"id" => id}) do
    Dataset
    |> Repo.get(id)
    |> import_data
    |> flash(conn,
            dgettext("backoffice", "Dataset imported with success"),
            dgettext("backoffice", "Dataset not imported")
      )
    |> redirect(to: backoffice_page_path(conn, :index))
  end

  def delete(%Plug.Conn{} = conn, %{"id" => id}) do
    Dataset
    |> Repo.get(id)
    |> Repo.delete()
    |> flash(conn, dgettext("backoffice_dataset", "Dataset deleted"), dgettext("backoffice", "Could not delete dataset"))
    |> redirect(to: backoffice_page_path(conn, :index))
  end

  def validation(%Plug.Conn{} = conn, %{"id" => id}) do
    Resource
    |> where([r], r.dataset_id ==  ^id)
    |> Repo.all()
    |> Enum.reduce(conn,
      fn r, conn -> r
        |> Resource.validate_and_save()
        |> flash(conn,
          dgettext("backoffice_dataset", "Dataset validated"),
          dgettext("backoffice_dataset", "Could not validate dataset")
        )
      end
    )
    |> redirect(to: backoffice_page_path(conn, :index))
  end

  ## Private functions

  defp flash({:error, message}, conn, _ok, err), do: put_flash(conn, :error, "#{err} (#{message})")
  defp flash({:ok, _message}, conn, ok_message, err_message), do: flash(:ok, conn, ok_message, err_message)
  defp flash(:ok,  conn, ok_message, _err_message), do: put_flash(conn, :info, ok_message)

  defp get_aom_id(%{"insee_commune_principale" => ""}), do: {:ok, nil}
  defp get_aom_id(%{"insee_commune_principale" => nil}), do: {:ok, nil}
  defp get_aom_id(%{"insee_commune_principale" => insee}) do
    case Repo.get_by(AOM, insee_commune_principale: insee) do
      nil -> {:error, dgettext("backoffice", "Unable to find INSEE")}
      aom -> {:ok, aom.id}
    end
  end

  defp import_data(%Dataset{} = dataset), do: import_data({:ok, dataset})
  defp import_data(nil), do: {:error, dgettext("backoffice", "Unable to find dataset")}
  defp import_data({:ok, dataset}), do: ImportDataService.call(dataset)
  defp import_data(error), do: error
end
