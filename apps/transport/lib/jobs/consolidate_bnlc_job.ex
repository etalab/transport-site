defmodule Transport.Jobs.ConsolidateBNLCJob do
  @moduledoc """
  Need to write some documentation
  """
  use Oban.Worker, max_attempts: 3
  require Logger
  alias Shared.Validation.TableSchemaValidator.Wrapper, as: TableSchemaValidator

  @schema_name "etalab/schema-lieux-covoiturage"
  @separator_key "csv_separator"
  @download_path_key "tmp_download_path"
  # You may need to change this URL if you're working locally on the code.
  # Maybe upload your own CSV to https://gist.github.com or return hardcoded
  # slugs from `datagouv_dataset_slugs`
  @datasets_list_csv_url "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/datasets.csv"
  @bnlc_github_url "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/bnlc-.csv"
  @bnlc_path System.tmp_dir!() |> Path.join("bnlc.csv")
  # The S3 bucket to use to upload the consolidated file, sent to our team for review.
  # We use the `:on_demand_validation` one because this is a bucket holding temporary
  # files.
  # If at some point we see that we need a bucket to hold consolidated files temporarily
  # we can create a specific one.
  @s3_bucket :on_demand_validation

  # Custom types
  @type consolidation_errors :: %{dataset_errors: list(), validation_errors: list(), download_errors: list()}
  @type dataset_without_appropriate_resource_error :: %{
          error: :not_at_least_one_appropriate_resource,
          dataset_details: map()
        }
  @type dataset_not_found_error :: %{error: :dataset_not_found, dataset_slug: binary()}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "delete_s3_file", "filename" => filename}}) do
    if filename |> String.starts_with?("bnlc") do
      Transport.S3.delete_object!(@s3_bucket, filename)
      Logger.info("Deleted #{filename} on S3")
      :ok
    else
      {:discard, "Cannot delete file, unexpected filename: #{inspect(filename)}"}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    return_value = consolidate()
    Oban.Notifier.notify(Oban, :gossip, %{complete: job_id})
    return_value
  end

  @spec consolidate() :: :ok | {:discard, binary()}
  def consolidate do
    Logger.info("Starting consolidation…")
    Logger.info("Extracting configured datasets & retrieving data from data.gouv…")
    %{ok: datasets_details, errors: dataset_errors} = datagouv_dataset_slugs() |> extract_dataset_details()

    Logger.info("Finding valid resources…")
    %{ok: resources_details, errors: validation_errors} = valid_datagouv_resources(datasets_details)

    if validation_errors |> Enum.filter(&match?({:validation_error, _, _}, &1)) |> Enum.any?() do
      {:discard, "Cannot consolidate the BNLC because the TableSchema validator is not available"}
    else
      Logger.info("Downloading resources…")
      %{ok: download_details, errors: download_errors} = download_resources(resources_details)
      Logger.info("Creating a single file")
      consolidate_resources(download_details)

      Logger.info("Sending the email recap")

      upload_temporary_file()
      |> schedule_deletion()
      |> send_email_recap(%{
        dataset_errors: dataset_errors,
        validation_errors: validation_errors,
        download_errors: download_errors
      })

      :ok
    end
  end

  defp upload_temporary_file do
    content = File.read!(@bnlc_path)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond) |> DateTime.to_string() |> String.replace(" ", "_")
    filename = "bnlc-#{now}.csv"
    Transport.S3.upload_to_s3!(@s3_bucket, content, filename)
    filename
  end

  defp schedule_deletion(filename) do
    # Delete temporary file in 4 weeks from S3
    %{action: "delete_s3_file", filename: filename}
    |> new(schedule_in: {4, :weeks})
    |> Oban.insert!()

    filename
  end

  @spec send_email_recap(binary(), consolidation_errors()) :: {:ok, any()} | {:error, any()}
  def send_email_recap(filename, %{} = errors) do
    {consolidation_status, body} =
      case format_errors(errors) do
        nil -> {:ok, "✅ La consolidation s'est déroulée sans erreurs"}
        txt when is_binary(txt) -> {:error, txt}
      end

    subject =
      case consolidation_status do
        :ok -> "[OK] Rapport de consolidation de la BNLC"
        :error -> "[ERREUR] Rapport de consolidation de la BNLC"
      end

    file_url = Transport.S3.permanent_url(@s3_bucket, filename)

    Transport.EmailSender.impl().send_mail(
      "transport.data.gouv.fr",
      Application.get_env(:transport, :contact_email),
      Application.get_env(:transport, :bizdev_email),
      Application.get_env(:transport, :contact_email),
      subject,
      "",
      """
      #{body}
      <br/><br/>
      🔗 <a href="#{file_url}">Fichier consolidé</a>
      """
    )
  end

  @spec format_errors(consolidation_errors()) :: binary() | nil
  def format_errors(%{dataset_errors: _, validation_errors: _, download_errors: _} = errors) do
    [&format_dataset_errors/1, &format_validation_errors/1, &format_download_errors/1]
    |> Enum.map_join("\n\n", fn fmt_fn -> fmt_fn.(errors) end)
    |> String.trim()
    |> case do
      "" -> nil
      txt when is_binary(txt) -> txt
    end
  end

  @spec format_dataset_errors(%{
          dataset_errors: [dataset_without_appropriate_resource_error() | dataset_not_found_error()]
        }) :: binary()
  def format_dataset_errors(%{dataset_errors: []}), do: ""

  def format_dataset_errors(%{dataset_errors: dataset_errors}) do
    format = fn el ->
      case el do
        %{error: :dataset_not_found, dataset_slug: slug} when is_binary(slug) ->
          "Le slug du jeu de données `#{slug}` est introuvable via l'API"

        %{error: :not_at_least_one_appropriate_resource, dataset_details: %{"page" => _, "title" => _} = dataset} ->
          "Pas de ressources avec le schéma #{@schema_name} pour #{link_to_dataset(dataset)}"
      end
    end

    """
    <h2>Erreurs liées aux jeux de données</h2>
    #{Enum.map_join(dataset_errors, "\n", fn el -> format.(el) end)}
    """
  end

  def format_validation_errors(%{validation_errors: []}), do: ""

  def format_validation_errors(%{validation_errors: validation_errors}) do
    """
    <h2>Ressources non valides par rapport au schéma #{@schema_name}</h2>
    #{Enum.map_join(validation_errors, "\n", &link_to_resource/1)}
    """
  end

  def format_download_errors(%{download_errors: []}), do: ""

  def format_download_errors(%{download_errors: download_errors}) do
    """
    <h2>Impossible de télécharger les ressources suivantes</h2>
    #{Enum.map_join(download_errors, "\n", &link_to_resource/1)}
    """
  end

  @doc """
  iex> link_to_dataset(%{"page" => "https://example.com", "title" => "Title"})
  ~s(<a href="https://example.com">Title</a>)
  """
  def link_to_dataset(%{"page" => page_url, "title" => title}) do
    title
    |> Phoenix.HTML.Link.link(to: page_url)
    |> Phoenix.HTML.safe_to_string()
  end

  @doc """
  iex> dataset = %{"page" => "https://example.com", "title" => "Title"}
  iex> resource = %{"schema" => %{"name" => "etalab/schema-lieux-covoiturage"}, "title" => "Foo"}
  iex> link_to_resource({dataset, resource})
  ~s{Ressource `Foo` (<a href="https://example.com">Title</a>)}
  iex> link_to_resource({:error, dataset, resource})
  ~s{Ressource `Foo` (<a href="https://example.com">Title</a>)}
  """
  def link_to_resource({:error, dataset_details, resource}), do: link_to_resource({dataset_details, resource})

  def link_to_resource({dataset_details, %{"title" => title, "schema" => %{"name" => schema_name}}})
      when schema_name == @schema_name do
    "Ressource `#{title}` (#{link_to_dataset(dataset_details)})"
  end

  @spec bnlc_csv_headers() :: [binary()]
  def bnlc_csv_headers do
    %HTTPoison.Response{body: body, status_code: 200} = @bnlc_github_url |> http_client().get!()
    [body] |> CSV.decode!(field_transform: &String.trim/1) |> Stream.take(1) |> Enum.to_list() |> hd()
  end

  @doc """
  Given a list of resources, previously prepared by `download_resources/1`,
  creates the BNLC final file and write on the local disk at `@bnlc_path`.

  It downloads the BNLC from GitHub and reads other files from the disk.
  """
  def consolidate_resources(resources_details) do
    file = File.open!(@bnlc_path, [:write, :utf8])
    bnlc_headers = bnlc_csv_headers()
    final_headers = ["id_lieu"] ++ bnlc_headers

    %HTTPoison.Response{body: body, status_code: 200} = @bnlc_github_url |> http_client().get!()

    # Write first the header + content of the BNLC hosted on GitHub
    [body]
    |> CSV.decode!(field_transform: &String.trim/1, headers: bnlc_headers)
    |> Stream.drop(1)
    |> add_id_lieu_column()
    |> CSV.encode(headers: final_headers)
    |> Enum.each(&IO.write(file, &1))

    # Append other valid resources to the file
    Enum.each(resources_details, fn {_dataset_detail, %{@download_path_key => tmp_path, @separator_key => separator}} ->
      tmp_path
      |> File.stream!()
      |> CSV.decode!(headers: true, field_transform: &String.trim/1, separator: separator)
      # Keep only columns that are present in the BNLC, ignore extra columns
      |> Stream.filter(&Map.take(&1, bnlc_headers))
      |> add_id_lieu_column()
      |> CSV.encode(headers: final_headers)
      # Don't write the CSV header again each time, it has already been written
      # because the BNLC is first in the file
      |> Stream.drop(1)
      |> Enum.each(&IO.write(file, &1))

      File.rm!(tmp_path)
    end)
  end

  defp add_id_lieu_column(%Stream{} = stream) do
    Stream.map(stream, fn %{"insee" => insee, "id_local" => id_local} = map ->
      Map.put(map, "id_lieu", "#{insee}-#{id_local}")
    end)
  end

  @doc """
  Reads the CSV file maintained by our team on GitHub listing datagouv dataset URLs
  we should include in the BNLC.
  Keep only dataset slugs.
  """
  @spec datagouv_dataset_slugs() :: [binary()]
  def datagouv_dataset_slugs do
    %HTTPoison.Response{body: body, status_code: 200} = @datasets_list_csv_url |> http_client().get!()

    [body]
    |> CSV.decode!(field_transform: &String.trim/1, headers: true)
    |> Stream.map(fn %{"dataset_url" => url} ->
      url
      |> String.replace_prefix(Application.fetch_env!(:transport, :datagouvfr_site) <> "/fr/datasets/", "")
      |> String.replace_suffix("/", "")
    end)
    |> Enum.uniq()
  end

  @doc """
  Guesses a CSV separator (`,` or `;`) from a CSV body, using only its first line (the header).
  """
  @spec guess_csv_separator(binary()) :: ?; | ?,
  def guess_csv_separator(body) do
    [?;, ?,]
    |> Enum.into(%{}, fn separator ->
      nb_columns_detected =
        [body]
        |> CSV.decode(headers: true, separator: separator)
        |> Stream.take(1)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, map} -> map |> Map.keys() |> Enum.count() end)

      {separator, nb_columns_detected}
    end)
    # Maximum number of columns detected is a good proxy to find the separator
    |> Enum.max_by(fn {_, v} -> v end)
    |> elem(0)
  end

  @doc """
  From a list of dataset slugs, call the data.gouv.fr's API and identify resources we are interested in.
  At this point, we only keep resources with the "covoiturage schema" declared, we don't perform further checks.

  Possible errors:
  - the dataset has no resources with the schema we are interested in
    `%{error: :not_at_least_one_appropriate_resource, dataset_details: map()}`
  - the data.gouv.fr's API returns an error for this dataset slug
    `%{error: :dataset_not_found, dataset_slug: binary()}`
  """
  @spec extract_dataset_details([binary()]) :: %{
          ok: [map()],
          errors: [dataset_without_appropriate_resource_error() | dataset_not_found_error()]
        }
  def extract_dataset_details(slugs) do
    slugs
    |> Enum.map(&get_dataset_details/1)
    |> normalize_ok_errors()
  end

  @spec get_dataset_details(binary()) ::
          {:ok, map()} | {:errors, dataset_without_appropriate_resource_error() | dataset_not_found_error()}
  defp get_dataset_details(slug) do
    case Datagouvfr.Client.Datasets.get(slug) do
      {:ok, %{"resources" => resources} = details} ->
        if resources |> Enum.filter(&with_appropriate_schema?/1) |> Enum.any?() do
          {:ok, details}
        else
          {:errors, %{error: :not_at_least_one_appropriate_resource, dataset_details: details}}
        end

      _ ->
        {:errors, %{error: :dataset_not_found, dataset_slug: slug}}
    end
  end

  @spec valid_datagouv_resources([map()]) :: %{
          ok: [],
          errors: [{:error, map(), map()} | {:validation_error, map(), map()}]
        }
  @doc """
  Identifies valid resources according to the target schema.
  For each resource, call the TableSchemaValidator to make sure the resource is valid.

  Possible errors:
  - the resource is not valid according to the schema ({`:error`, _, _})
  - the validator is not available ({`:validation_error`, _, _})
  """
  def valid_datagouv_resources(datasets_details) do
    analyze_resource = fn dataset_details, %{"url" => resource_url} = resource ->
      case TableSchemaValidator.validate(@schema_name, resource_url) do
        %{"has_errors" => true} -> {:errors, {:error, dataset_details, resource}}
        %{"has_errors" => false} -> {:ok, {dataset_details, resource}}
        nil -> {:errors, {:validation_error, dataset_details, resource}}
      end
    end

    analyze_dataset = fn %{"resources" => resources} = dataset_details ->
      resources
      |> Enum.filter(&with_appropriate_schema?/1)
      |> Enum.map(fn %{"url" => _} = resource -> analyze_resource.(dataset_details, resource) end)
    end

    datasets_details |> Enum.flat_map(&analyze_dataset.(&1)) |> normalize_ok_errors()
  end

  @doc """
  From a list of resource object coming from the data.gouv.fr's API, download these (valid)
  CSV files locally and guess the CSV separator.

  The temporary download path and the guessed CSV separator are added to the resource's payload.

  Possible errors:
  - cannot download the resource
  """
  @spec download_resources([map()]) :: %{ok: [], errors: []}
  def download_resources(resources_details) do
    resources_details
    |> Enum.map(fn {dataset_details, %{"id" => resource_id, "url" => resource_url} = resource} ->
      case http_client().get(resource_url, [], follow_redirect: true) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          path = System.tmp_dir!() |> Path.join("consolidate_bnlc_#{resource_id}")
          File.write!(path, body)
          resource = Map.merge(resource, %{@download_path_key => path, @separator_key => guess_csv_separator(body)})
          {:ok, {dataset_details, resource}}

        _ ->
          {:errors, {dataset_details, resource}}
      end
    end)
    |> normalize_ok_errors()
  end

  @doc """
  Make sure we always have `:ok` and `:errors` keys.

  iex> normalize_ok_errors(%{})
  %{ok: [], errors: []}
  iex> normalize_ok_errors(%{ok: [1]})
  %{ok: [1], errors: []}
  iex> normalize_ok_errors(%{ok: [1], errors: [2]})
  %{ok: [1], errors: [2]}
  iex> normalize_ok_errors([{:ok, 1}, {:errors, 2}])
  %{errors: [2], ok: [1]}
  """
  def normalize_ok_errors(result) when is_list(result),
    do: result |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)) |> normalize_ok_errors()

  def normalize_ok_errors(result) when is_map(result), do: Map.merge(%{ok: [], errors: []}, result)

  @doc """
  iex> with_appropriate_schema?(%{"schema" => %{"name" => "foo"}})
  false
  iex> with_appropriate_schema?(%{"schema" => %{"name" => "etalab/schema-lieux-covoiturage"}})
  true
  iex> with_appropriate_schema?(%{"description" => "Chapeaux ronds"})
  false
  """
  @spec with_appropriate_schema?(map()) :: boolean()
  def with_appropriate_schema?(%{"schema" => %{"name" => name}}) when name == @schema_name, do: true
  def with_appropriate_schema?(%{}), do: false

  @doc """
  iex> dataset_slug_to_url("foo")
  "https://www.data.gouv.fr/fr/datasets/foo/"
  """
  def dataset_slug_to_url(slug) do
    "https://www.data.gouv.fr/fr/datasets/#{slug}/"
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
