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
  @datasets_list_csv_url "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/datasets.csv"
  @bnlc_github_url "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/bnlc-.csv"
  @bnlc_path "/tmp/bnlc.csv"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    :ok
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
    headers = bnlc_csv_headers()

    %HTTPoison.Response{body: body, status_code: 200} = @bnlc_github_url |> http_client().get!()

    # Write first the header + content of the BNLC hosted on GitHub
    [body]
    |> CSV.decode!(field_transform: &String.trim/1, headers: headers)
    |> Stream.drop(1)
    |> CSV.encode(headers: headers)
    |> Enum.each(&IO.write(file, &1))

    # Append other valid resources to the file
    Enum.each(resources_details, fn {_dataset_detail, %{@download_path_key => tmp_path, @separator_key => separator}} ->
      tmp_path
      |> File.stream!()
      |> Stream.drop(1)
      |> CSV.decode!(field_transform: &String.trim/1, separator: separator)
      |> CSV.encode(headers: false)
      |> Enum.each(&IO.write(file, &1))
    end)
  end

  @doc """
  Reads the CSV file maintained by our team on GitHub listing dataset URLs we should include in the BNLC.
  Keep only dataset slugs.
  """
  @spec dataset_slugs() :: [binary()]
  def dataset_slugs do
    %HTTPoison.Response{body: body, status_code: 200} = @datasets_list_csv_url |> http_client().get!()

    [body]
    |> CSV.decode!(field_transform: &String.trim/1, headers: true)
    |> Stream.map(fn %{"dataset_url" => url} ->
      url
      |> String.replace("https://www.data.gouv.fr/fr/datasets/", "")
      |> String.replace_suffix("/", "")
    end)
    |> Enum.to_list()
    |> Enum.uniq()
  end

  @doc """
  Guesses a CSV separator (`,` or `;`) from a CSV body, using only its first line (the header).
  """
  @spec guess_csv_separator(binary()) :: char()
  def guess_csv_separator(body) do
    [?;, ?,]
    |> Enum.into(%{}, fn separator ->
      nb_columns =
        [body]
        |> CSV.decode(headers: true, separator: separator)
        |> Stream.take(1)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, map} -> map |> Map.keys() |> Enum.count() end)

      {separator, nb_columns}
    end)
    |> Enum.max_by(fn {_, v} -> v end)
    |> elem(0)
  end

  @doc """
  From a list of dataset slugs, call the data.gouv.fr's API and identify resources we are interested in.
  At this point, we only keep resources with the "covoiturage schema" declared, we don't perform further checks.

  Possible errors:
  - the dataset has no resources with the schema we are interested in
  - the data.gouv.fr's API returns an error for this dataset slug
  """
  @spec dataset_details([binary()]) :: %{ok: [map()], errors: [binary() | map()]}
  def dataset_details(slugs) do
    filter_resources = fn acc, %{"resources" => resources} = details ->
      if resources |> Enum.filter(&with_appropriate_schema?/1) |> Enum.any?() do
        Map.put(acc, :ok, [details | Map.fetch!(acc, :ok)])
      else
        Map.put(acc, :errors, [details | Map.fetch!(acc, :errors)])
      end
    end

    analyze_dataset = fn slug, %{ok: _, errors: _} = acc ->
      case Datagouvfr.Client.Datasets.get(slug) do
        {:ok, %{"resources" => _} = details} ->
          filter_resources.(acc, details)

        _ ->
          Map.put(acc, :errors, [dataset_slug_to_url(slug) | Map.fetch!(acc, :errors)])
      end
    end

    Enum.reduce(slugs, %{ok: [], errors: []}, fn slug, acc -> analyze_dataset.(slug, acc) end)
  end

  @spec valid_datagouv_resources([map()]) :: %{ok: [], errors: []}
  def valid_datagouv_resources(datasets_details) do
    analyze_resource = fn dataset_details, %{"url" => resource_url} = resource ->
      case TableSchemaValidator.validate(@schema_name, resource_url) do
        %{"has_errors" => true} -> {:error, dataset_details, resource}
        %{"has_errors" => false} -> {:ok, dataset_details, resource}
        nil -> {:validation_error, dataset_details, resource}
      end
    end

    analyze_dataset = fn %{"resources" => resources} = dataset_details, %{ok: _, errors: _} = acc ->
      {oks, errors} =
        resources
        |> Enum.filter(&with_appropriate_schema?/1)
        |> Enum.map(fn %{"url" => _} = resource -> analyze_resource.(dataset_details, resource) end)
        |> Enum.split_with(&match?({:ok, %{}, %{}}, &1))

      acc
      |> Map.keys()
      |> Enum.into(%{}, fn key ->
        existing_value = Map.fetch!(acc, key)

        {key,
         case key do
           :ok -> oks |> Enum.map(fn {:ok, dataset, resource} -> {dataset, resource} end) |> Kernel.++(existing_value)
           :errors -> errors ++ existing_value
         end}
      end)
    end

    Enum.reduce(datasets_details, %{ok: [], errors: []}, fn dataset_details, acc ->
      analyze_dataset.(dataset_details, acc)
    end)
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
    download_resource = fn
      {dataset_details, %{"id" => resource_id, "url" => resource_url} = resource}, %{ok: _, errors: _} = acc ->
        case http_client().get(resource_url, [], follow_redirect: true) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            path = System.tmp_dir!() |> Path.join("consolidate_bnlc_#{resource_id}")
            File.write!(path, body)
            resource = Map.merge(resource, %{@download_path_key => path, @separator_key => guess_csv_separator(body)})
            Map.put(acc, :ok, [{dataset_details, resource} | Map.fetch!(acc, :ok)])

          _ ->
            Map.put(acc, :errors, [{dataset_details, resource} | Map.fetch!(acc, :errors)])
        end
    end

    Enum.reduce(resources_details, %{ok: [], errors: []}, fn payload, acc ->
      download_resource.(payload, acc)
    end)
  end

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
