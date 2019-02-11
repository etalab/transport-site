defmodule TransportWeb.Backoffice.DatasetController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.Datasets

  alias Transport.{AOM, Dataset, ImportData, Repo, Resource}
  import Ecto.Query

  def new_dataset(%Plug.Conn{} = conn, params) do
    with datagouv_id when not is_nil(datagouv_id) <- Datasets.get_id_from_url(conn, params["url"]),
         {:ok, dataset} <- ImportData.import_from_udata(datagouv_id, params["type"]),
         {:ok, aom_id} <- get_aom_id(params),
         params <- Map.merge(params, dataset),
         params <- Map.put(params, "aom_id", aom_id)
    do
      datagouv_id
      |> get_or_new_dataset()
      |> Dataset.changeset(params)
      |> Repo.insert_or_update()
      |> flash(
        conn,
        dgettext("backoffice_dataset", "Dataset added with success"),
        dgettext("backoffice_dataset", "Could not add dataset")
      )
    else
      {:error, error} ->
        conn
        |> put_flash(:error, dgettext("backoffice_dataset", "Could not add dataset"))
        |> put_flash(:error, error)
    end
    |> redirect_to_index()
  end

  def import_from_data_gouv_fr(%Plug.Conn{} = conn, %{"id" => id}) do
    Dataset
    |> Repo.get(id)
    |> import_data
    |> flash(conn,
            dgettext("backoffice_dataset", "Dataset imported with success"),
            dgettext("backoffice_dataset", "Dataset not imported")
      )
    |> redirect_to_index()
  end

  def delete(%Plug.Conn{} = conn, %{"id" => id}) do
    Dataset
    |> Repo.get(id)
    |> Repo.delete()
    |> flash(conn, dgettext("backoffice_dataset", "Dataset deleted"), dgettext("backoffice", "Could not delete dataset"))
    |> redirect_to_index()
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
    |> redirect_to_index()
  end

  ## Private functions

  defp flash({:ok, _message}, conn, ok_message, err_message), do: flash(:ok, conn, ok_message, err_message)
  defp flash(:ok,  conn, ok_message, _err_message), do: put_flash(conn, :info, ok_message)
  defp flash({:error, %{errors: errors}},  conn, _ok, err_message) do
    errors_messages = for {_, {m, _}} <- errors, do: m
    messages = errors_messages ++ [err_message] |> Enum.uniq()
    put_flash(conn, :error, Enum.join(messages, ", "))
  end
  defp flash({:error, message}, conn, _ok, err), do: put_flash(conn, :error, "#{err} (#{message})")

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
  defp import_data({:ok, dataset}), do: ImportData.call(dataset)
  defp import_data(error), do: error

  defp get_or_new_dataset(datagouv_id) do
    case Repo.get_by(Dataset, datagouv_id: datagouv_id) do
      nil -> %Dataset{}
      dataset -> dataset
    end
  end

  defp redirect_to_index(conn), do: redirect(conn, to: backoffice_page_path(conn, :index, conn.params |> Map.take(["q"])))
end
