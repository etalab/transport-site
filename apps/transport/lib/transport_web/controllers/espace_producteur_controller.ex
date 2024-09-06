defmodule TransportWeb.EspaceProducteurController do
  use TransportWeb, :controller
  require Logger
  alias Transport.ImportData

  plug(:find_dataset_and_fetch_from_api_or_redirect when action in [:edit_dataset, :new_resource])

  plug(
    :find_db_dataset_and_api_dataset_and_resource_or_redirect
    when action in [:delete_resource_confirmation, :edit_resource]
  )

  plug(:find_dataset_or_redirect when action in [:upload_logo, :remove_custom_logo])
  plug(:find_datasets_or_redirect when action in [:proxy_statistics])

  def edit_dataset(%Plug.Conn{} = conn, %{"dataset_id" => _}) do
    # Awkard page, but no real choice: some parts (logo…) are from the local database
    # While resources list is from the API
    # Producer wants to edit the dataset and has perhaps just done it: we need fresh info
    conn |> render("edit_dataset.html")
  end

  def upload_logo(
        %Plug.Conn{assigns: %{dataset: %DB.Dataset{datagouv_id: datagouv_id}}} = conn,
        %{"upload" => %{"file" => %Plug.Upload{path: filepath, filename: filename}}}
      ) do
    destination_path = "tmp_#{datagouv_id}#{extension(filename)}"
    Transport.S3.stream_to_s3!(:logos, filepath, destination_path)

    %{datagouv_id: datagouv_id, path: destination_path}
    |> Transport.Jobs.CustomLogoConversionJob.new()
    |> Oban.insert!()

    conn
    |> put_flash(:info, dgettext("espace-producteurs", "Your logo has been received. It will be replaced soon."))
    |> redirect(to: page_path(conn, :espace_producteur))
  end

  defp extension(filename), do: filename |> Path.extname() |> String.downcase()

  def remove_custom_logo(%Plug.Conn{assigns: %{dataset: %DB.Dataset{} = dataset}} = conn, _) do
    %DB.Dataset{custom_logo: custom_logo, custom_full_logo: custom_full_logo, datagouv_id: datagouv_id} = dataset
    bucket_url = Transport.S3.permanent_url(:logos) <> "/"

    [custom_logo, custom_full_logo]
    |> Enum.map(fn url -> String.replace(url, bucket_url, "") end)
    |> Enum.each(fn path -> Transport.S3.delete_object!(:logos, path) end)

    {:ok, %Ecto.Changeset{} = changeset} =
      DB.Dataset.changeset(%{"datagouv_id" => datagouv_id, "custom_logo" => nil, "custom_full_logo" => nil})

    DB.Repo.update!(changeset)

    conn
    |> put_flash(:info, dgettext("espace-producteurs", "Your custom logo has been removed."))
    |> redirect(to: page_path(conn, :espace_producteur))
  end

  @spec proxy_statistics(Plug.Conn.t(), map) :: Plug.Conn.t()
  def proxy_statistics(%Plug.Conn{assigns: %{datasets: datasets}} = conn, _params) do
    proxy_stats =
      datasets
      |> Enum.flat_map(& &1.resources)
      |> Enum.filter(&DB.Resource.served_by_proxy?/1)
      # Gotcha: this is a N+1 problem. Okay as long as a single producer
      # does not have a lot of feeds/there is not a lot of traffic on this page
      |> Enum.into(%{}, fn %DB.Resource{id: id} = resource ->
        {id, DB.Metrics.requests_over_last_days(resource, proxy_requests_stats_nb_days())}
      end)

    conn
    |> assign(:proxy_stats, proxy_stats)
    |> assign(:proxy_requests_stats_nb_days, proxy_requests_stats_nb_days())
    |> render("proxy_statistics.html")
  end

  @spec new_resource(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def new_resource(conn, %{"dataset_id" => _dataset_id}) do
    conn
    |> assign(:datagouv_resource, nil)
    |> render("resource_form.html")
  end

  @spec edit_resource(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def edit_resource(conn, %{"dataset_id" => _dataset_id, "resource_datagouv_id" => _resource_datagouv_id}) do
    conn
    |> render("resource_form.html")
  end

  def delete_resource_confirmation(%Plug.Conn{} = conn, %{
        "dataset_id" => _dataset_datagouv_id,
        "resource_datagouv_id" => _resource_datagouv_id
      }) do
    conn
    |> render("delete_resource_confirmation.html")
  end

  def delete_resource(%Plug.Conn{} = conn, %{
        "dataset_datagouv_id" => dataset_datagouv_id,
        "resource_datagouv_id" => resource_datagouv_id
      }) do
    with {:ok, _} <-
           Datagouvfr.Client.Resources.delete(conn, %{
             "dataset_id" => dataset_datagouv_id,
             "resource_id" => resource_datagouv_id
           }),
         dataset when not is_nil(dataset) <-
           DB.Repo.get_by(DB.Dataset, datagouv_id: dataset_datagouv_id),
         {:ok, _} <- ImportData.import_dataset_logged(dataset),
         {:ok, _} <- DB.Dataset.validate(dataset) do
      conn
      |> put_flash(:info, dgettext("resource", "The resource has been deleted"))
      |> redirect(to: page_path(conn, :espace_producteur))
    else
      _ ->
        conn
        |> put_flash(:error, dgettext("resource", "Could not delete the resource"))
        |> redirect(to: page_path(conn, :espace_producteur))
    end
  end

  @spec post_file(Plug.Conn.t(), map) :: Plug.Conn.t()
  def post_file(conn, params) do
    success_message =
      if Map.has_key?(params, "resource_file") do
        dgettext("resource", "File uploaded!")
      else
        dgettext("resource", "Resource updated with URL!")
      end

    post_params = datagouv_api_update_params(params)

    with {:ok, _} <- Datagouvfr.Client.Resources.update(conn, post_params),
         dataset when not is_nil(dataset) <-
           DB.Repo.get_by(DB.Dataset, datagouv_id: params["dataset_datagouv_id"]),
         {:ok, _} <- ImportData.import_dataset_logged(dataset),
         {:ok, _} <- DB.Dataset.validate(dataset) do
      conn
      |> put_flash(:info, success_message)
      |> redirect(to: dataset_path(conn, :details, params["dataset_datagouv_id"]))
    else
      {:error, error} ->
        Logger.error(
          "Unable to update resource #{params["resource_datagouv_id"]} of dataset #{params["dataset_datagouv_id"]}, error: #{inspect(error)}"
        )

        conn
        |> put_flash(:error, dgettext("resource", "Unable to upload file"))
        |> redirect(to: page_path(conn, :espace_producteur))

      nil ->
        Logger.error("Unable to get dataset with datagouv_id: #{params["dataset_datagouv_id"]}")

        conn
        |> put_flash(:error, dgettext("resource", "Unable to upload file"))
        |> redirect(to: page_path(conn, :espace_producteur))
    end
  end

  defp proxy_requests_stats_nb_days, do: 15

  defp find_datasets_or_redirect(%Plug.Conn{} = conn, _options) do
    conn
    |> DB.Dataset.datasets_for_user()
    |> case do
      datasets when is_list(datasets) ->
        conn |> assign(:datasets, datasets)

      {:error, _} ->
        conn
        |> put_flash(:error, dgettext("alert", "Unable to get all your resources for the moment"))
        |> redirect(to: page_path(conn, :espace_producteur))
        |> halt()
    end
  end

  defp find_dataset_or_redirect(%Plug.Conn{path_params: %{"dataset_id" => dataset_id}} = conn, _options) do
    case find_dataset_for_user(conn, dataset_id) do
      %DB.Dataset{} = dataset ->
        conn |> assign(:dataset, dataset)

      nil ->
        conn
        |> put_flash(:error, dgettext("alert", "Unable to get this dataset for the moment"))
        |> redirect(to: page_path(conn, :espace_producteur))
        |> halt()
    end
  end

  defp find_dataset_and_fetch_from_api_or_redirect(
         %Plug.Conn{path_params: %{"dataset_id" => dataset_id}} = conn,
         _options
       ) do
    with %DB.Dataset{datagouv_id: datagouv_id} = dataset <- find_dataset_for_user(conn, dataset_id),
         {:ok, datagouv_dataset} <- Datagouvfr.Client.Datasets.get(datagouv_id) do
      conn
      |> assign(:dataset, dataset)
      |> assign(:datagouv_dataset, datagouv_dataset)
    else
      _ ->
        conn
        |> put_flash(:error, dgettext("alert", "Unable to get this dataset for the moment"))
        |> redirect(to: page_path(conn, :espace_producteur))
        |> halt()
    end
  end

  # Ugly but we’ll pipe plugs afterward. TODO.
  defp find_db_dataset_and_api_dataset_and_resource_or_redirect(
         %Plug.Conn{path_params: %{"dataset_id" => dataset_id, "resource_datagouv_id" => resource_datagouv_id}} = conn,
         _options
       ) do
    with %DB.Dataset{datagouv_id: datagouv_id} = dataset <- find_dataset_for_user(conn, dataset_id),
         {:ok, datagouv_dataset} <- Datagouvfr.Client.Datasets.get(datagouv_id),
         datagouv_resource when not is_nil(datagouv_resource) <-
           assign_resource_from_dataset_payload(datagouv_dataset, resource_datagouv_id) do
      conn
      |> assign(:dataset, dataset)
      |> assign(:datagouv_dataset, datagouv_dataset)
      |> assign(:datagouv_resource, datagouv_resource)
    else
      _ ->
        conn
        |> put_flash(:error, dgettext("alert", "Unable to get this dataset for the moment"))
        |> redirect(to: page_path(conn, :espace_producteur))
        |> halt()
    end
  end

  @spec find_dataset_for_user(Plug.Conn.t(), binary()) :: DB.Dataset.t() | nil
  defp find_dataset_for_user(%Plug.Conn{} = conn, dataset_id_str) do
    {dataset_id, ""} = Integer.parse(dataset_id_str)

    conn
    |> DB.Dataset.datasets_for_user()
    |> case do
      datasets when is_list(datasets) -> datasets
      {:error, _} -> []
    end
    |> Enum.find(fn %DB.Dataset{id: id} -> id == dataset_id end)
  end

  defp assign_resource_from_dataset_payload(dataset, resource_id) do
    Enum.find(dataset["resources"], &(&1["id"] == resource_id))
  end

  defp datagouv_api_update_params(params) do
    post_params = Map.put(params, "dataset_id", params["dataset_datagouv_id"])

    post_params =
      if params["resource_datagouv_id"] do
        Map.put(post_params, "resource_id", params["resource_datagouv_id"])
      else
        post_params
      end

    Map.take(post_params, ["title", "format", "url", "resource_file", "dataset_id", "resource_id"])
  end
end
