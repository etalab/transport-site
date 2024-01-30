defmodule TransportWeb.EspaceProducteurController do
  use TransportWeb, :controller

  plug(:find_dataset_or_redirect when action in [:edit_dataset, :upload_logo])

  def edit_dataset(%Plug.Conn{} = conn, %{"dataset_id" => _}) do
    conn |> render("edit_dataset.html")
  end

  def upload_logo(%Plug.Conn{} = conn, %{"dataset_id" => _, "upload" => %{"file" => %Plug.Upload{} = file}}) do
    conn
    |> upload_logo_and_send_email(file)
    |> put_flash(:info, dgettext("espace-producteurs", "Your logo has been received. We will get back to you soon."))
    |> redirect(to: page_path(conn, :espace_producteur))
  end

  defp upload_logo_and_send_email(
         %Plug.Conn{
           assigns: %{
             current_user: current_user,
             dataset: %DB.Dataset{datagouv_id: datagouv_id, custom_title: custom_title}
           }
         } = conn,
         %Plug.Upload{path: filepath, filename: filename}
       ) do
    extension = filename |> Path.extname() |> String.downcase()
    destination_path = "tmp_#{datagouv_id}#{extension}"
    Transport.S3.stream_to_s3!(:logos, filepath, destination_path)

    subject = "Logo personnalisé : #{custom_title}"

    """
    Bonjour,

    Un logo personnalisé vient d'être envoyé.

    Scripts à exécuter :
    s3cmd get s3://#{Transport.S3.bucket_name(:logos)}/#{destination_path} /tmp/#{destination_path}
    elixir scripts/custom_logo.exs /tmp/#{destination_path} #{datagouv_id}
    s3cmd rm s3://#{Transport.S3.bucket_name(:logos)}/#{destination_path}

    Personne à contacter :
    #{current_user["email"]}
    """
    |> Transport.CustomLogoNotifier.custom_logo(subject)
    |> Transport.Mailer.deliver()

    conn
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

defmodule Transport.CustomLogoNotifier do
  import Swoosh.Email

  def custom_logo(text_body, subject) do
    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> to(Application.fetch_env!(:transport, :contact_email))
    |> subject(subject)
    |> text_body(text_body)
  end
end
