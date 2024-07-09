defmodule TransportWeb.EspaceProducteurController do
  use TransportWeb, :controller

  plug(:find_dataset_or_redirect when action in [:edit_dataset, :upload_logo, :remove_custom_logo])
  plug(:find_datasets_or_redirect when action in [:proxy_statistics])

  def edit_dataset(%Plug.Conn{} = conn, %{"dataset_id" => _}) do
    # This page is linked to the resources edition form, but we show on the table the latest resource in database
    # While the resource edition page shows the latest resource from the API…
    # This can lead to confusive links
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
end
