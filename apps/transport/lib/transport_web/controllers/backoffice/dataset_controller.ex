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

    dataset_id = Datasets.get_id_from_url(params["url"])

    with datagouv_id when not is_nil(datagouv_id) <- dataset_id,
         {:ok, dg_dataset} <- ImportData.import_from_data_gouv(datagouv_id, params["type"]),
         params <- Map.merge(params, dg_dataset),
         {:ok, changeset} <- Dataset.changeset(params),
         {:ok, dataset} <- insert_dataset(changeset) do
      dataset
      |> Dataset.validate()
      |> flash(
        conn,
        [
          msgs.success[params["action"]],
          ". ",
          Phoenix.HTML.Link.link(
            dgettext("backoffice_dataset", "Check the dataset page"),
            to: dataset_path(conn, :details, dataset_id)
          )
        ],
        msgs.error[params["action"]]
      )
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
  def import_from_data_gouv_fr(%Plug.Conn{} = conn, %{"id" => id, "stay_on_page" => "true"}),
    do: redirect(import_from_data_gouv_fr_aux(conn, id), to: backoffice_page_path(conn, :edit, id))

  def import_from_data_gouv_fr(%Plug.Conn{} = conn, %{"id" => id}),
    do: redirect_to_index(import_from_data_gouv_fr_aux(conn, id))

  @spec import_from_data_gouv_fr_aux(Plug.Conn.t(), integer()) :: Plug.Conn.t()
  defp import_from_data_gouv_fr_aux(conn, id) do
    Dataset
    |> Repo.get(id)
    |> import_data
    |> flash(
      conn,
      dgettext("backoffice_dataset", "Dataset imported with success"),
      dgettext("backoffice_dataset", "Dataset not imported")
    )
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

  @spec import_validate_all(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def import_validate_all(%Plug.Conn{} = conn, _args) do
    ImportDataWorker.import_validate_all()

    conn
    |> put_flash(
      :info,
      dgettext("backoffice_dataset", "Import and validation of all datasets have been launch")
    )
    |> redirect_to_index()
  end

  @spec validate_all(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def validate_all(%Plug.Conn{} = conn, _args) do
    ImportDataWorker.validate_all()

    conn
    |> put_flash(
      :info,
      dgettext("backoffice_dataset", "validation of all datasets has been launched")
    )
    |> redirect_to_index()
  end

  @spec force_validate_all(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def force_validate_all(%Plug.Conn{} = conn, _args) do
    ImportDataWorker.force_validate_all()

    conn
    |> put_flash(
      :info,
      dgettext("backoffice_dataset", "validation of all datasets has been launch")
    )
    |> redirect_to_index()
  end

  @spec force_validate_gtfs_transport(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def force_validate_gtfs_transport(%Plug.Conn{} = conn, _args) do
    ImportDataWorker.force_validate_gtfs_transport()

    conn
    |> put_flash(
      :info,
      dgettext(
        "backoffice_dataset",
        "GTFS Transport Validator has been force launched on all GTFS resources"
      )
    )
    |> redirect_to_index()
  end

  ## Private functions

  @spec flash(:ok | {:ok, any} | {:error, any}, Plug.Conn.t(), iodata(), iodata()) :: Plug.Conn.t()
  defp flash({:ok, _message}, conn, ok_message, err_message),
    do: flash(:ok, conn, ok_message, err_message)

  defp flash(:ok, conn, ok_message, _err_message), do: put_flash(conn, :info, ok_message)

  defp flash({:error, %{errors: errors}}, conn, _ok, err_message) do
    errors_messages = for {_, {m, _}} <- errors, do: m
    messages = (errors_messages ++ [err_message]) |> Enum.uniq()
    put_flash(conn, :error, Enum.join(messages, ", "))
  end

  defp flash({:error, message}, conn, _ok, err),
    do: put_flash(conn, :error, "#{err} (#{message})")

  @spec import_data(Dataset.t() | nil) :: any()
  defp import_data(%Dataset{} = dataset), do: ImportData.import_dataset_logged(dataset)
  defp import_data(nil), do: {:error, dgettext("backoffice", "Unable to find dataset")}

  defp redirect_to_index(conn),
    do: redirect(conn, to: backoffice_page_path(conn, :index, conn.params |> Map.take(["q"])))
end
