defmodule Transport.Jobs.ConsolidateBNLCJob do
  @moduledoc """
  Need to write some documentation
  """
  use Oban.Worker, max_attempts: 3
  require Logger
  alias Shared.Validation.TableSchemaValidator.Wrapper, as: TableSchemaValidator

  @schema_name "etalab/schema-lieux-covoiturage"
  @download_path_key "tmp_download_path"
  @datasets_list_csv_url "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/datasets.csv"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    :ok
  end

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

  @spec download_resources([map()]) :: %{ok: [], errors: []}
  def download_resources(resources_details) do
    download_resource = fn
      {:ok, dataset_details, %{"id" => resource_id, "url" => resource_url} = resource}, %{ok: _, errors: _} = acc ->
        case http_client().get(resource_url, [], follow_redirect: true) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            path = System.tmp_dir!() |> Path.join("consolidate_bnlc_#{resource_id}")
            File.write!(path, body)
            resource = Map.put(resource, @download_path_key, path)
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
