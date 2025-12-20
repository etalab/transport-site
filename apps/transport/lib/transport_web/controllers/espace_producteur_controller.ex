defmodule TransportWeb.EspaceProducteurController do
  use TransportWeb, :controller
  require Logger
  alias Transport.ImportData
  import Ecto.Query

  plug(
    :find_db_dataset_and_api_dataset_or_redirect
    when action in [:edit_dataset, :new_resource, :reuser_improved_data]
  )

  plug(
    :find_db_dataset_and_api_dataset_and_resource_or_redirect
    when action in [:delete_resource_confirmation, :edit_resource]
  )

  plug(:find_db_dataset_or_redirect when action in [:upload_logo, :remove_custom_logo])
  plug(:find_db_datasets_or_redirect when action in [:proxy_statistics, :download_statistics])

  plug(:assign_current_contact when action in [:delete_resource, :post_file, :upload_logo])

  def edit_dataset(%Plug.Conn{assigns: %{dataset: %DB.Dataset{} = dataset}} = conn, %{"dataset_id" => _}) do
    # Awkard page, but no real choice: some parts (logo…) are from the local database
    # While resources list is from the API
    # Producer wants to edit the dataset and has perhaps just done it: we need fresh info
    conn
    |> assign(:dataset, dataset |> DB.Repo.preload(reuser_improved_data: [:resource]))
    |> render("edit_dataset.html")
  end

  def reuser_improved_data(%Plug.Conn{assigns: %{dataset: %DB.Dataset{id: dataset_id}}} = conn, %{
        "resource_id" => resource_id
      }) do
    reuser_improved_data =
      DB.ReuserImprovedData
      |> where([rid], rid.dataset_id == ^dataset_id and rid.resource_id == ^resource_id)
      |> preload(:organization)
      |> DB.Repo.all()

    conn
    |> assign(:resource, DB.Repo.get!(DB.Resource, resource_id))
    |> assign(:reuser_improved_data, reuser_improved_data)
    |> render("reuser_improved_data.html")
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

    DB.FeatureUsage.insert!(:upload_logo, conn.assigns.current_contact.id, %{
      dataset_datagouv_id: datagouv_id
    })

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

  def download_statistics(%Plug.Conn{assigns: %{datasets: datasets}} = conn, _params) do
    resources = Enum.flat_map(datasets, & &1.resources) |> Enum.filter(&DB.Resource.hosted_on_datagouv?/1)
    year = Date.utc_today().year
    download_stats = DB.ResourceMonthlyMetric.downloads_for_year(resources, year)

    conn
    |> assign(:download_stats, download_stats)
    |> assign(:datasets, datasets)
    |> assign(:year, year)
    |> render("download_statistics.html")
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
      Appsignal.increment_counter("espace_producteur.delete_resource.success", 1)

      DB.FeatureUsage.insert!(:delete_resource, conn.assigns.current_contact.id, %{
        dataset_datagouv_id: dataset_datagouv_id,
        resource_datagouv_id: resource_datagouv_id
      })

      conn
      |> put_flash(:info, dgettext("resource", "The resource has been deleted"))
      |> redirect(to: page_path(conn, :espace_producteur))
    else
      _ ->
        Appsignal.increment_counter("espace_producteur.delete_resource.error", 1)

        conn
        |> put_flash(:error, dgettext("resource", "Could not delete the resource"))
        |> redirect(to: page_path(conn, :espace_producteur))
    end
  end

  @doc """
  The following function does a POST to the datagouv API to update or create a resource.
  We don’t check that the user is allowed to update the dataset, as the API will do it for us.
  We don’t check either before the POST that the dataset is imported on our side.
  In case of error, the user is redirected to the producer space with an error message
  instead of rendering again the form: it’s a suboptimal experience, can be improved.
  """
  @spec post_file(Plug.Conn.t(), map) :: Plug.Conn.t()
  def post_file(conn, %{"dataset_datagouv_id" => dataset_datagouv_id} = params) do
    success_message =
      if Map.has_key?(params, "resource_file") do
        dgettext("resource", "File uploaded!")
      else
        dgettext("resource", "Resource updated with URL!")
      end

    post_params = datagouv_api_update_params(params)

    with {:ok, _} <- Datagouvfr.Client.Resources.update(conn, post_params),
         dataset when not is_nil(dataset) <-
           DB.Repo.get_by(DB.Dataset, datagouv_id: dataset_datagouv_id),
         {:ok, _} <- ImportData.import_dataset_logged(dataset),
         {:ok, _} <- DB.Dataset.validate(dataset) do
      Appsignal.increment_counter("espace_producteur.post_file.success", 1)

      DB.FeatureUsage.insert!(:upload_file, conn.assigns.current_contact.id, %{
        dataset_datagouv_id: dataset_datagouv_id
      })

      conn
      |> put_flash(:info, success_message)
      |> redirect(to: dataset_path(conn, :details, params["dataset_datagouv_id"]))
    else
      {:error, error} ->
        Appsignal.increment_counter("espace_producteur.post_file.error", 1)

        Logger.error(
          "Unable to update resource #{params["resource_datagouv_id"]} of dataset #{params["dataset_datagouv_id"]}, error: #{inspect(error)}"
        )

        conn
        |> put_flash(:error, dgettext("resource", "Unable to upload file"))
        |> redirect(to: page_path(conn, :espace_producteur))

      nil ->
        Appsignal.increment_counter("espace_producteur.post_file.error", 1)
        Logger.error("Unable to get dataset with datagouv_id: #{params["dataset_datagouv_id"]}")

        conn
        |> put_flash(:error, dgettext("resource", "Unable to upload file"))
        |> redirect(to: page_path(conn, :espace_producteur))
    end
  end

  defp proxy_requests_stats_nb_days, do: 15

  defp find_db_datasets_or_redirect(%Plug.Conn{} = conn, _options) do
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

  defp find_db_dataset_or_redirect(%Plug.Conn{path_params: %{"dataset_id" => dataset_id}} = conn, _options) do
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

  defp find_db_dataset_and_api_dataset_or_redirect(
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

  defp assign_current_contact(%Plug.Conn{assigns: %{current_user: current_user}} = conn, _options) do
    current_contact =
      if is_nil(current_user) do
        nil
      else
        DB.Contact |> DB.Repo.get_by!(datagouv_user_id: Map.fetch!(current_user, "id"))
      end

    assign(conn, :current_contact, current_contact)
  end
end
