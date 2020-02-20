defmodule TransportWeb.Backoffice.DatasetController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.Datasets

  alias DB.{Dataset, ImportDataWorker, Repo}
  alias Transport.{ImportData, ImportDataWorker}
  require Logger

  @spec post(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def post(%Plug.Conn{} = conn, params) do
    msgs = %{
      success: %{
        "edit" => dgettext("backoffice_dataset", "Dataset edited with success"),
        "new" => dgettext("backoffice_dataset", "Dataset added with success")
      },
      error: %{
        "edit" => dgettext("backoffice_dataset", "Could not edit dataset"),
        "new" => dgettext("backoffice_dataset", "Could not add dataset")
      }
    }

    with datagouv_id when not is_nil(datagouv_id) <- Datasets.get_id_from_url(params["url"]),
         {:ok, dg_dataset} <- ImportData.import_from_udata(datagouv_id, params["type"]),
         params <- Map.merge(params, dg_dataset),
         {:ok, changeset} <- Dataset.changeset(params),
         {:ok, dataset} <- insert_dataset(changeset) do
      dataset
      |> Dataset.validate()
      |> flash(conn, msgs.success[params["action"]], msgs.error[params["action"]])
    else
      {:error, error} ->
        conn
        |> put_flash(:error, msgs.error[params["action"]])
        |> put_flash(:error, error)

      error ->
        Logger.error(error)

        conn
        |> put_flash(:error, msgs.error[params["action"]])
        |> put_flash(:error, "Unable to get datagouv id")
    end
    |> redirect_to_index()
  end

  @spec insert_dataset(Ecto.Changeset.t()) :: {:ok, binary} | {:error, binary}
  defp insert_dataset(changeset) do
    Repo.insert_or_update(changeset)
  rescue
    exception in Ecto.ConstraintError ->
      Logger.error("Constraint violation while inserting dataset: #{inspect(exception)}")

      {:error, "Problem while inserting the dataset in the database,
       a constraint has not been respected : '#{exception.constraint}'"}
  end

  @spec import_from_data_gouv_fr(Plug.Conn.t(), map) :: Plug.Conn.t()
  def import_from_data_gouv_fr(%Plug.Conn{} = conn, %{"id" => id}) do
    Dataset
    |> Repo.get(id)
    |> import_data
    |> flash(
      conn,
      dgettext("backoffice_dataset", "Dataset imported with success"),
      dgettext("backoffice_dataset", "Dataset not imported")
    )
    |> redirect_to_index()
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(%Plug.Conn{} = conn, %{"id" => id}) do
    Dataset
    |> Repo.get(id)
    |> Repo.delete()
    |> flash(
      conn,
      dgettext("backoffice_dataset", "Dataset deleted"),
      dgettext("backoffice", "Could not delete dataset")
    )
    |> redirect_to_index()
  end

  @spec validate_all(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def validate_all(%Plug.Conn{} = conn, _args) do
    ImportDataWorker.all()

    conn
    |> put_flash(:info, dgettext("backoffice_dataset", "Import and validation of all datasets have been launch"))
    |> redirect_to_index()
  end

  ## Private functions

  @spec flash(:ok | {:ok, any} | {:error, any}, Plug.Conn.t(), binary, binary) :: Plug.Conn.t()
  defp flash({:ok, _message}, conn, ok_message, err_message), do: flash(:ok, conn, ok_message, err_message)
  defp flash(:ok, conn, ok_message, _err_message), do: put_flash(conn, :info, ok_message)

  defp flash({:error, %{errors: errors}}, conn, _ok, err_message) do
    errors_messages = for {_, {m, _}} <- errors, do: m
    messages = (errors_messages ++ [err_message]) |> Enum.uniq()
    put_flash(conn, :error, Enum.join(messages, ", "))
  end

  defp flash({:error, message}, conn, _ok, err), do: put_flash(conn, :error, "#{err} (#{message})")

  @spec import_data(Dataset.t() | nil) :: any()
  defp import_data(%Dataset{} = dataset), do: ImportData.call(dataset)
  defp import_data(nil), do: {:error, dgettext("backoffice", "Unable to find dataset")}

  defp redirect_to_index(conn),
    do: redirect(conn, to: backoffice_page_path(conn, :index, conn.params |> Map.take(["q"])))
end
