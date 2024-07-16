defmodule Transport.Jobs.CustomLogoConversionJob do
  @moduledoc """
  A job to handle custom logos uploaded by producers.
  It converts images (resize and thumbnail), upload them to the
  object storage and updates the dataset.
  """
  use Oban.Worker, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"datagouv_id" => datagouv_id, "path" => path}, inserted_at: %DateTime{} = inserted_at}) do
    %DB.Dataset{datagouv_id: datagouv_id} = DB.Repo.get_by!(DB.Dataset, datagouv_id: datagouv_id)
    local_path = Path.join(System.tmp_dir!(), path)
    extension = local_path |> Path.extname() |> String.downcase()
    timestamp = DateTime.to_unix(inserted_at)

    logo_filename = "#{datagouv_id}.#{timestamp}#{extension}"
    full_logo_filename = "#{datagouv_id}_full.#{timestamp}#{extension}"
    logo_path = Path.join(System.tmp_dir!(), logo_filename)
    full_logo_path = Path.join(System.tmp_dir!(), full_logo_filename)

    Transport.S3.download_file(:logos, path, local_path)

    local_path
    |> Image.thumbnail!(100)
    |> Image.flatten!(background_color: :white)
    |> Image.embed!(100, 100, background_color: :white, extend_mode: :white)
    |> Image.write!(logo_path)

    local_path
    |> Image.thumbnail!(500)
    |> Image.flatten!(background_color: :white)
    |> Image.write!(full_logo_path)

    stream_to_s3(logo_path, logo_filename)
    stream_to_s3(full_logo_path, full_logo_filename)

    {:ok, %Ecto.Changeset{} = changeset} =
      %{
        "datagouv_id" => datagouv_id,
        "custom_logo" => Transport.S3.permanent_url(:logos, logo_filename),
        "custom_full_logo" => Transport.S3.permanent_url(:logos, full_logo_filename)
      }
      |> DB.Dataset.changeset()

    DB.Repo.update!(changeset)

    File.rm!(local_path)
    Transport.S3.delete_object!(:logos, path)

    :ok
  end

  defp stream_to_s3(local_path, remote_path) do
    Transport.S3.stream_to_s3!(:logos, local_path, remote_path,
      acl: :public_read,
      cache_control: "public, max-age=604800"
    )
  end
end
