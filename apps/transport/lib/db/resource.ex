defmodule DB.Resource do
  @moduledoc """
  Resource model
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.{Dataset, Repo, ResourceUnavailability}
  import Ecto.{Changeset, Query}
  import TransportWeb.Router.Helpers, only: [resource_url: 3]
  require Logger

  typed_schema "resource" do
    # real url
    field(:url, :string)
    field(:format, :string)
    field(:last_import, :string)
    field(:title, :string)
    field(:last_update, :string)
    # stable data.gouv.fr url if exists, else (for ODS gtfs as csv) it's the real url
    field(:latest_url, :string)
    field(:is_available, :boolean, default: true)

    field(:is_community_resource, :boolean)

    # the declared official schema used by the resource
    field(:schema_name, :string)
    field(:schema_version, :string)

    # only relevant for community resources, name of the owner or the organization that published the resource
    field(:community_resource_publisher, :string)
    field(:description, :string)

    # some community resources have been generated from another dataset (like the generated NeTEx / GeoJson)
    field(:original_resource_url, :string)

    # Id of the datagouv resource. Note that several resources can have the same datagouv_id
    # because one datagouv resource can be a CSV linking to several transport.data.gouv's resources
    # (this is done for OpenDataSoft)
    field(:datagouv_id, :string)

    field(:filesize, :integer)
    # Can be `remote` or `file`. `file` are for files uploaded and hosted
    # on data.gouv.fr
    field(:filetype, :string)
    # The resource's type on data.gouv.fr
    # https://github.com/opendatateam/udata/blob/fab505fd9159c6a9f63e3cb55f0d6479b7ca91e2/udata/core/dataset/models.py#L89-L96
    # Example: `main`, `documentation`, `api`, `code` etc.
    field(:type, :string)
    field(:display_position, :integer)

    belongs_to(:dataset, Dataset)

    has_many(:validations, DB.MultiValidation)
    has_many(:resource_metadata, DB.ResourceMetadata)

    has_many(:resource_unavailabilities, ResourceUnavailability,
      on_replace: :delete,
      on_delete: :delete_all
    )

    has_many(:resource_history, DB.ResourceHistory)
  end

  def base_query, do: from(r in DB.Resource, as: :resource)

  def join_dataset_with_resource(query) do
    query
    |> join(:inner, [dataset: d], r in DB.Resource, on: d.id == r.dataset_id, as: :resource)
  end

  def filter_on_resource_id(query, resource_id) do
    query
    |> where([resource: r], r.id == ^resource_id)
  end

  def filter_on_dataset_id(query, dataset_id) do
    query
    |> where([resource: r], r.dataset_id == ^dataset_id)
  end

  @spec endpoint() :: binary()
  def endpoint, do: Application.fetch_env!(:transport, :gtfs_validator_url) <> "/validate"

  def changeset(resource, params) do
    resource
    |> cast(
      params,
      [
        :url,
        :format,
        :last_import,
        :title,
        :id,
        :datagouv_id,
        :last_update,
        :latest_url,
        :is_available,
        :is_community_resource,
        :schema_name,
        :schema_version,
        :community_resource_publisher,
        :original_resource_url,
        :description,
        :filesize,
        :filetype,
        :type,
        :display_position
      ]
    )
    |> validate_required([:url, :datagouv_id])
  end

  @spec is_gtfs?(__MODULE__.t()) :: boolean()
  def is_gtfs?(%__MODULE__{format: "GTFS"}), do: true
  def is_gtfs?(_), do: false

  @spec is_gbfs?(__MODULE__.t()) :: boolean
  def is_gbfs?(%__MODULE__{format: "gbfs"}), do: true
  def is_gbfs?(_), do: false

  @spec is_netex?(__MODULE__.t()) :: boolean
  def is_netex?(%__MODULE__{format: "NeTEx"}), do: true
  def is_netex?(_), do: false

  @spec is_gtfs_rt?(__MODULE__.t()) :: boolean
  def is_gtfs_rt?(%__MODULE__{format: "gtfs-rt"}), do: true
  def is_gtfs_rt?(%__MODULE__{format: "gtfsrt"}), do: true
  def is_gtfs_rt?(_), do: false

  @spec is_siri?(__MODULE__.t()) :: boolean
  def is_siri?(%__MODULE__{format: "SIRI"}), do: true
  def is_siri?(_), do: false

  @spec is_siri_lite?(__MODULE__.t()) :: boolean
  def is_siri_lite?(%__MODULE__{format: "SIRI Lite"}), do: true
  def is_siri_lite?(_), do: false

  @spec is_documentation?(__MODULE__.t()) :: boolean
  def is_documentation?(%__MODULE__{type: "documentation"}), do: true
  def is_documentation?(_), do: false

  @spec is_community_resource?(__MODULE__.t()) :: boolean
  def is_community_resource?(%__MODULE__{is_community_resource: true}), do: true
  def is_community_resource?(_), do: false

  @spec is_real_time?(__MODULE__.t()) :: boolean
  def is_real_time?(%__MODULE__{} = resource) do
    is_gtfs_rt?(resource) or is_gbfs?(resource) or is_siri_lite?(resource) or is_siri?(resource)
  end

  @doc """
  Ultimately, requestor_refs should be imported as data gouv meta-data, or maybe just set via
  our backoffice. For now though, we're guessing them based on a public configuration + the host name.

  iex> guess_requestor_ref(%DB.Resource{format: "SIRI", url: "https://ara-api.enroute.mobi/endpoint"})
  "fake-enroute-requestor-ref"
  iex> guess_requestor_ref(%DB.Resource{format: "GTFS", url: "https://ara-api.enroute.mobi/gtfs.zip"})
  nil
  iex> guess_requestor_ref(%DB.Resource{format: "SIRI", url: "https://example.com/endpoint"})
  nil
  iex> guess_requestor_ref(%DB.Resource{format: "GTFS", url: "https://example.com/gtfs.zip"})
  nil
  """
  def guess_requestor_ref(%__MODULE__{url: url} = resource) do
    if is_siri?(resource) do
      host_to_key = Application.fetch_env!(:transport, :public_siri_host_mappings)

      resource_host = URI.parse(url).host

      :transport
      |> Application.fetch_env!(:public_siri_requestor_refs)
      |> Map.get(host_to_key[resource_host])
    else
      nil
    end
  end

  @spec has_schema?(__MODULE__.t()) :: boolean
  def has_schema?(%__MODULE__{schema_name: schema_name}), do: not is_nil(schema_name)

  @spec can_direct_download?(__MODULE__.t()) :: boolean
  def can_direct_download?(resource) do
    # raw.githubusercontent.com does not put `Content-Disposition: attachment`
    # in response headers and we'd like to have this
    uri = URI.parse(resource.url)
    uri.scheme == "https" and uri.host != "raw.githubusercontent.com"
  end

  @spec other_resources_query(__MODULE__.t()) :: Ecto.Query.t()
  def other_resources_query(%__MODULE__{} = resource),
    do:
      from(
        r in __MODULE__,
        where: r.dataset_id == ^resource.dataset_id and r.id != ^resource.id
      )

  @spec other_resources(__MODULE__.t()) :: [__MODULE__.t()]
  def other_resources(%__MODULE__{} = r),
    do:
      r
      |> other_resources_query()
      |> Repo.all()

  def by_id(query, id) do
    from(resource in query,
      where: resource.id == ^id
    )
  end

  @spec get_related_files(__MODULE__.t()) :: map()
  def get_related_files(%__MODULE__{id: resource_id}) do
    %{}
    |> Map.put(:geojson, get_related_geojson_info(resource_id))
    |> Map.put(:netex, get_related_netex_info(resource_id))
  end

  def get_related_geojson_info(resource_id), do: get_related_conversion_info(resource_id, "GeoJSON")
  def get_related_netex_info(resource_id), do: get_related_conversion_info(resource_id, "NeTEx")

  @spec get_related_conversion_info(integer() | nil, binary()) ::
          %{url: binary(), filesize: binary(), resource_history_last_up_to_date_at: DateTime.t()} | nil
  def get_related_conversion_info(nil, _), do: nil

  def get_related_conversion_info(resource_id, format) do
    DB.ResourceHistory
    |> join(:inner, [rh], dc in DB.DataConversion,
      as: :dc,
      on: fragment("? = (?->>'uuid')::uuid", dc.resource_history_uuid, rh.payload)
    )
    |> select([rh, dc], %{
      url: fragment("? ->> 'permanent_url'", dc.payload),
      filesize: fragment("? ->> 'filesize'", dc.payload),
      resource_history_last_up_to_date_at: rh.last_up_to_date_at
    })
    |> where([rh, dc], rh.resource_id == ^resource_id and dc.convert_to == ^format)
    |> order_by([rh, _], desc: rh.inserted_at)
    |> limit(1)
    |> DB.Repo.one()
  end

  @spec content_updated_at(integer() | __MODULE__.t()) :: Calendar.datetime() | nil
  def content_updated_at(%__MODULE__{id: id}), do: content_updated_at(id)

  def content_updated_at(resource_id) do
    resource_history_list =
      DB.ResourceHistory
      |> where([rh], rh.resource_id == ^resource_id)
      |> where([rh], fragment("payload \\? 'download_datetime'"))
      |> select([rh], fragment("payload ->>'download_datetime'"))
      |> order_by([rh], desc: fragment("payload ->>'download_datetime'"))
      |> limit(2)
      |> DB.Repo.all()

    case Enum.count(resource_history_list) do
      n when n in [0, 1] ->
        nil

      _ ->
        {:ok, updated_at, 0} = resource_history_list |> Enum.at(0) |> DateTime.from_iso8601()
        updated_at
    end
  end

  def download_url(%__MODULE__{} = resource, conn_or_endpoint \\ TransportWeb.Endpoint) do
    cond do
      needs_stable_url?(resource) -> resource.latest_url
      can_direct_download?(resource) -> resource.url
      true -> resource_url(conn_or_endpoint, :download, resource.id)
    end
  end

  defp needs_stable_url?(%__MODULE__{latest_url: nil}), do: false

  defp needs_stable_url?(%__MODULE__{url: url}) do
    parsed_url = URI.parse(url)

    hosted_on_static_datagouv =
      Enum.member?(Application.fetch_env!(:transport, :datagouv_static_hosts), parsed_url.host)

    object_storage_regex =
      ~r{(https://.*\.blob\.core\.windows\.net)|(https://.*\.s3\..*\.amazonaws\.com)|(https://.*\.s3\..*\.scw\.cloud)|(https://.*\.cellar-c2\.services\.clever-cloud\.com)|(https://s3\..*\.cloud\.ovh\.net)}

    hosted_on_bison_fute = parsed_url.host == Application.fetch_env!(:transport, :bison_fute_host)

    cond do
      hosted_on_bison_fute -> is_link_to_folder?(parsed_url)
      hosted_on_static_datagouv -> true
      String.match?(url, object_storage_regex) -> true
      true -> false
    end
  end

  defp needs_stable_url?(%__MODULE__{}), do: false

  defp is_link_to_folder?(%URI{path: path}) do
    path |> Path.basename() |> :filename.extension() == ""
  end

  @doc """
  iex> served_by_proxy?(%DB.Resource{url: "https://transport.data.gouv.fr/gbfs/marseille/gbfs.json", format: "gbfs"})
  true
  iex> served_by_proxy?(%DB.Resource{url: "https://proxy.transport.data.gouv.fr/resource/axeo-guingamp-gtfs-rt-vehicle-position", format: "gtfs-rt"})
  true
  iex> served_by_proxy?(%DB.Resource{url: "https://example.com", format: "GTFS"})
  false
  """
  def served_by_proxy?(%__MODULE__{url: url} = resource) do
    cond do
      is_gtfs_rt?(resource) -> URI.parse(url).host == "proxy.transport.data.gouv.fr"
      is_gbfs?(resource) -> String.starts_with?(url, "https://transport.data.gouv.fr/gbfs/")
      true -> false
    end
  end

  @doc """
  iex> proxy_slug(%DB.Resource{url: "https://transport.data.gouv.fr/gbfs/cergy-pontoise/gbfs.json", format: "gbfs"})
  "cergy-pontoise"
  iex> proxy_slug(%DB.Resource{url: "https://proxy.transport.data.gouv.fr/resource/axeo-guingamp-gtfs-rt-vehicle-position", format: "gtfs-rt"})
  "axeo-guingamp-gtfs-rt-vehicle-position"
  iex> proxy_slug(%DB.Resource{url: "https://example.com", format: "GTFS"})
  nil
  """
  def proxy_slug(%__MODULE__{url: url} = resource) do
    if served_by_proxy?(resource) do
      cond do
        is_gtfs_rt?(resource) ->
          url |> URI.parse() |> Map.fetch!(:path) |> String.replace("/resource/", "")

        is_gbfs?(resource) ->
          ~r{^https://transport\.data\.gouv\.fr/gbfs/([a-zA-Z0-9_-]+)/} |> Regex.run(url) |> List.last()
      end
    else
      nil
    end
  end
end
