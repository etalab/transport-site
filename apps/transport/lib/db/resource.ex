defmodule DB.Resource do
  @moduledoc """
  Resource model
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.{Dataset, Repo, ResourceUnavailability}
  import Ecto.{Changeset, Query}
  import TransportWeb.Router.Helpers, only: [conversion_url: 4, resource_url: 3, resource_url: 4]
  require Logger

  typed_schema "resource" do
    # The resource's real URL
    field(:url, :string)
    field(:format, :string)
    field(:last_import, :utc_datetime_usec)
    field(:title, :string)
    field(:last_update, :utc_datetime_usec)
    # data.gouv.fr's stable URL:
    # - for resources hosted on data.gouv.fr it redirects to static.data.gouv.fr
    # - for others, it points to the final URL
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

    # a JSON field used to compute and keep a counter cache of costly
    # elements, so that queries can be optimized
    field(:counter_cache, :map)

    belongs_to(:dataset, Dataset)

    has_many(:validations, DB.MultiValidation)
    has_many(:resource_metadata, DB.ResourceMetadata)

    has_many(:resource_unavailabilities, ResourceUnavailability,
      on_replace: :delete,
      on_delete: :delete_all
    )

    has_many(:resource_history, DB.ResourceHistory)

    has_many(
      :resources_related,
      DB.ResourceRelated,
      references: :id,
      foreign_key: :resource_src_id,
      on_replace: :delete
    )
  end

  def base_query, do: from(r in DB.Resource, as: :resource)

  def join_dataset_with_resource(query) do
    query
    |> join(:inner, [dataset: d], r in DB.Resource, on: d.id == r.dataset_id, as: :resource)
  end

  def filter_on_resource_id(query, resource_id) do
    query |> where([resource: r], r.id == ^resource_id)
  end

  def filter_on_dataset_id(query, dataset_id) do
    query |> where([resource: r], r.dataset_id == ^dataset_id)
  end

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
    |> no_schema_name_for_public_transport()
  end

  @spec gtfs?(__MODULE__.t()) :: boolean()
  def gtfs?(%__MODULE__{format: "GTFS"}), do: true
  def gtfs?(_), do: false

  @spec gbfs?(__MODULE__.t()) :: boolean
  def gbfs?(%__MODULE__{format: "gbfs"}), do: true
  def gbfs?(_), do: false

  @spec netex?(__MODULE__.t()) :: boolean
  def netex?(%__MODULE__{format: "NeTEx"}), do: true
  def netex?(_), do: false

  @spec gtfs_rt?(__MODULE__.t()) :: boolean
  def gtfs_rt?(%__MODULE__{format: "gtfs-rt"}), do: true
  def gtfs_rt?(%__MODULE__{format: "gtfsrt"}), do: true
  def gtfs_rt?(_), do: false

  @spec siri?(__MODULE__.t()) :: boolean
  def siri?(%__MODULE__{format: "SIRI"}), do: true
  def siri?(_), do: false

  @spec siri_lite?(__MODULE__.t()) :: boolean
  def siri_lite?(%__MODULE__{format: "SIRI Lite"}), do: true
  def siri_lite?(_), do: false

  @spec documentation?(__MODULE__.t()) :: boolean
  def documentation?(%__MODULE__{type: "documentation"}), do: true
  def documentation?(_), do: false

  @spec community_resource?(__MODULE__.t()) :: boolean
  def community_resource?(%__MODULE__{is_community_resource: true}), do: true
  def community_resource?(_), do: false

  @doc """
  iex> real_time?(%DB.Resource{format: "gbfs"})
  true
  iex> real_time?(%DB.Resource{format: "GTFS"})
  false
  iex> real_time?(%DB.Resource{format: "csv", description: "Données mises à jour en temps réel"})
  true
  """
  @spec real_time?(__MODULE__.t()) :: boolean
  def real_time?(%__MODULE__{} = resource) do
    [
      &gtfs_rt?/1,
      &gbfs?/1,
      &siri_lite?/1,
      &siri?/1,
      &String.contains?(&1.description || "", ["mis à jour en temps réel", "mises à jour en temps réel"])
    ]
    |> Enum.any?(fn function -> function.(resource) end)
  end

  @doc """
  iex> requestor_ref(%DB.Resource{format: "SIRI", dataset: %DB.Dataset{custom_tags: ["requestor_ref:foo"]}})
  "foo"
  iex> requestor_ref(%DB.Resource{format: "GTFS", dataset: %DB.Dataset{}})
  nil
  iex> requestor_ref(%DB.Resource{format: "SIRI", dataset: %DB.Dataset{}})
  nil
  """
  def requestor_ref(%__MODULE__{format: "SIRI", dataset: %DB.Dataset{} = dataset}) do
    Enum.find_value(dataset.custom_tags || [], fn tag ->
      prefix = "requestor_ref:"
      if String.starts_with?(tag, prefix), do: String.replace_prefix(tag, prefix, "")
    end)
  end

  def requestor_ref(%__MODULE__{}), do: nil

  @spec has_schema?(__MODULE__.t()) :: boolean
  def has_schema?(%__MODULE__{schema_name: schema_name}), do: not is_nil(schema_name)

  @spec can_direct_download?(__MODULE__.t()) :: boolean
  def can_direct_download?(resource) do
    # raw.githubusercontent.com does not put `Content-Disposition: attachment`
    # in response headers and we'd like to have this
    uri = URI.parse(resource.url)
    uri.scheme == "https" and uri.host != "raw.githubusercontent.com"
  end

  @doc """
  Is the resource published by the National Access Point?

  iex> pan_resource?(%DB.Resource{dataset: %DB.Dataset{organization_id: "5abca8d588ee386ee6ece479"}})
  true
  iex> pan_resource?(%DB.Resource{dataset: %DB.Dataset{organization_id: "other"}})
  false
  iex> pan_resource?(%DB.Resource{format: "gbfs"})
  false
  """
  @spec pan_resource?(__MODULE__.t()) :: boolean()
  def pan_resource?(%__MODULE__{dataset: %DB.Dataset{organization_id: organization_id}}) do
    organization_id == Application.fetch_env!(:transport, :datagouvfr_transport_publisher_id)
  end

  def pan_resource?(%__MODULE__{}), do: false

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
    |> Map.put(:GeoJSON, get_related_geojson_info(resource_id))
  end

  def get_related_geojson_info(resource_id), do: get_related_conversion_info(resource_id, :GeoJSON)

  @spec get_related_conversion_info(integer() | nil, :GeoJSON) ::
          %{url: binary(), stable_url: binary(), filesize: binary(), resource_history_last_up_to_date_at: DateTime.t()}
          | nil
  def get_related_conversion_info(nil, _), do: nil

  def get_related_conversion_info(resource_id, format) do
    converter = DB.DataConversion.converter_to_use(format)
    # Only value supported for now but needed to make the query fast
    # https://github.com/etalab/transport-site/issues/4448
    convert_from = :GTFS

    DB.ResourceHistory
    |> join(:inner, [rh], dc in DB.DataConversion,
      as: :dc,
      on: fragment("? = (?->>'uuid')::uuid", dc.resource_history_uuid, rh.payload)
    )
    |> select([rh, dc], %{
      url: fragment("? ->> 'permanent_url'", dc.payload),
      filesize: fragment("(? ->> 'filesize')::int", dc.payload),
      resource_history_last_up_to_date_at: rh.last_up_to_date_at
    })
    |> where(
      [rh, dc],
      rh.resource_id == ^resource_id and
        dc.convert_from == ^convert_from and dc.convert_to == ^format and
        dc.status == :success and dc.converter == ^converter
    )
    |> order_by([rh, _], desc: rh.inserted_at)
    |> limit(1)
    |> DB.Repo.one()
    |> case do
      nil ->
        nil

      %{} = data ->
        Map.put(data, :stable_url, conversion_url(TransportWeb.Endpoint, :get, resource_id, format))
    end
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

  def download_url(%__MODULE__{} = resource) do
    download_url(resource, TransportWeb.Endpoint)
  end

  # When the contact is logged in and has a default token
  def download_url(
        %__MODULE__{} = resource,
        %Plug.Conn{
          assigns: %{current_contact: %DB.Contact{default_tokens: [%DB.Token{} = token]}}
        } = conn
      ) do
    if pan_resource?(resource) do
      resource_url(conn, :download, resource.id, token: token.secret)
    else
      download_url(resource, TransportWeb.Endpoint)
    end
  end

  def download_url(%__MODULE__{} = resource, conn_or_endpoint) do
    cond do
      pan_resource?(resource) -> resource_url(conn_or_endpoint, :download, resource.id)
      needs_stable_url?(resource) -> resource.latest_url
      can_direct_download?(resource) -> resource.url
      true -> resource_url(conn_or_endpoint, :download, resource.id)
    end
  end

  @doc """
  iex> hosted_on_datagouv?(%DB.Resource{url: "https://static.data.gouv.fr/file.zip"})
  true
  iex> hosted_on_datagouv?("https://static.data.gouv.fr/file.zip")
  true
  iex> hosted_on_datagouv?(%DB.Resource{url: "https://example.com/file.zip"})
  false
  """
  @spec hosted_on_datagouv?(__MODULE__.t() | binary()) :: boolean()
  def hosted_on_datagouv?(url) when is_binary(url), do: hosted_on_datagouv?(%__MODULE__{url: url})

  def hosted_on_datagouv?(%__MODULE__{url: url}) do
    host = url |> URI.parse() |> Map.fetch!(:host)
    Enum.member?(Application.fetch_env!(:transport, :datagouv_static_hosts), host)
  end

  defp needs_stable_url?(%__MODULE__{latest_url: nil}), do: false

  defp needs_stable_url?(%__MODULE__{url: url} = resource) do
    parsed_url = URI.parse(url)

    object_storage_regex =
      ~r{(https://.*\.blob\.core\.windows\.net)|(https://.*\.s3\..*\.amazonaws\.com)|(https://.*\.s3\..*\.scw\.cloud)|(https://.*\.cellar-c2\.services\.clever-cloud\.com)|(https://s3\..*\.cloud\.ovh\.net)}

    hosted_on_bison_fute = parsed_url.host == Application.fetch_env!(:transport, :bison_fute_host)

    cond do
      hosted_on_bison_fute -> link_to_folder?(parsed_url)
      hosted_on_datagouv?(resource) -> true
      String.match?(url, object_storage_regex) -> true
      true -> false
    end
  end

  defp link_to_folder?(%URI{path: path}) do
    path |> Path.basename() |> :filename.extension() == ""
  end

  @doc """
  iex> served_by_proxy?(%DB.Resource{url: "https://transport.data.gouv.fr/gbfs/marseille/gbfs.json", format: "gbfs"})
  true
  iex> served_by_proxy?(%DB.Resource{url: "https://proxy.transport.data.gouv.fr/resource/axeo-guingamp-gtfs-rt-vehicle-position", format: "gtfs-rt"})
  true
  iex> served_by_proxy?(%DB.Resource{url: "https://example.com", format: "GTFS"})
  false
  iex> served_by_proxy?(%DB.Resource{url: "https://proxy.transport.data.gouv.fr/resource/sncf-siri-lite-situation-exchange", format: "SIRI Lite"})
  true
  """
  def served_by_proxy?(%__MODULE__{url: url}) do
    Enum.any?(
      ["https://transport.data.gouv.fr/gbfs/", "https://proxy.transport.data.gouv.fr"],
      &String.starts_with?(url, &1)
    )
  end

  @doc """
  iex> proxy_slug(%DB.Resource{url: "https://transport.data.gouv.fr/gbfs/cergy-pontoise/gbfs.json", format: "gbfs"})
  "cergy-pontoise"
  iex> proxy_slug(%DB.Resource{url: "https://proxy.transport.data.gouv.fr/resource/axeo-guingamp-gtfs-rt-vehicle-position", format: "gtfs-rt"})
  "axeo-guingamp-gtfs-rt-vehicle-position"
  iex> proxy_slug(%DB.Resource{url: "https://proxy.transport.data.gouv.fr/resource/sncf-siri-lite-situation-exchange", format: "SIRI Lite"})
  "sncf-siri-lite-situation-exchange"
  iex> proxy_slug(%DB.Resource{url: "https://example.com", format: "GTFS"})
  nil
  """
  def proxy_slug(%__MODULE__{url: url} = resource) do
    if served_by_proxy?(resource) do
      cond do
        String.starts_with?(url, "https://proxy.transport.data.gouv.fr") ->
          url |> URI.parse() |> Map.fetch!(:path) |> String.replace("/resource/", "")

        String.starts_with?(url, "https://transport.data.gouv.fr/gbfs/") ->
          ~r{^https://transport\.data\.gouv\.fr/gbfs/([a-zA-Z0-9_-]+)/} |> Regex.run(url) |> List.last()
      end
    else
      nil
    end
  end

  @doc """
  The proxy namespace for a resource. Defined in other Umbrella apps (`gbfs` and `unlock`).
  Used in `metrics.target` and `metrics.event`.

  iex> proxy_namespace(%DB.Resource{url: "https://transport.data.gouv.fr/gbfs/cergy-pontoise/gbfs.json", format: "gbfs"})
  "gbfs"
  iex> proxy_namespace(%DB.Resource{url: "https://proxy.transport.data.gouv.fr/resource/axeo-guingamp-gtfs-rt-vehicle-position", format: "gtfs-rt"})
  "proxy"
  """
  def proxy_namespace(%__MODULE__{format: "gbfs"}), do: "gbfs"
  def proxy_namespace(%__MODULE__{}), do: "proxy"

  def no_schema_name_for_public_transport(%Ecto.Changeset{} = changeset) do
    schema_name = get_field(changeset, :schema_name)
    format = get_field(changeset, :format)
    public_transport_formats = ["GTFS", "gtfs-rt", "NeTEx", "SIRI", "SIRI Lite"]

    if format in public_transport_formats and is_binary(schema_name) do
      changeset
      |> add_error(:schema_name, "Public transport formats can’t have a schema set",
        resource_id: get_field(changeset, :id),
        resource_datagouv_id: get_field(changeset, :datagouv_id)
      )
    else
      changeset
    end
  end
end
