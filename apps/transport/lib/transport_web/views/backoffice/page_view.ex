defmodule TransportWeb.Backoffice.PageView do
  use TransportWeb, :view
  alias DB.Dataset
  alias Plug.Conn.Query
  alias TransportWeb.PaginationHelpers

  def pagination_links(conn, datasets, anchor \\ "") do
    custom_path =
      if anchor != "" do
        fn conn, action, params -> "#{backoffice_page_path(conn, action, params)}##{anchor}" end
      else
        &backoffice_page_path/3
      end

    kwargs = [path: custom_path] |> add_filter(conn.params)

    PaginationHelpers.pagination_links(conn, datasets, kwargs)
  end

  @spec add_filter(list, map) :: list
  defp add_filter(kwargs, params) do
    params
    # filter allowed keys
    |> Map.take(["filter", "q", "order_by", "dir"])
    |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
    |> Enum.concat(kwargs)
  end

  @spec backoffice_sort_link(Plug.Conn.t(), String.t(), atom, %{field: atom, direction: atom}) ::
          any
  def backoffice_sort_link(conn, text, order_by, current_order) do
    dir =
      case current_order.field == order_by do
        false ->
          :asc

        true ->
          case current_order.direction do
            :asc -> :desc
            _ -> :asc
          end
      end

    params =
      conn.query_params
      |> Map.put("order_by", order_by)
      |> Map.put("dir", dir)

    full_url =
      conn.request_path
      |> URI.parse()
      |> Map.put(:query, Query.encode(params))
      |> URI.to_string()
      |> Kernel.<>("#backoffice-datasets-table")

    sort_arrow = get_arrow(current_order.field == order_by, current_order.direction)
    link(raw("#{text} #{sort_arrow}"), to: full_url)
  end

  @spec get_arrow(boolean, atom) :: <<_::64, _::_*8>>
  defp get_arrow(column_is_sorted, direction) do
    case {column_is_sorted, direction} do
      {false, _} ->
        "<i class=\"sort-icon fa fa-sort\"></i>"

      {true, :asc} ->
        "<i class=\"sort-icon fa fa-sort-down\"></i>"

      {true, :desc} ->
        "<i class=\"sort-icon fa fa-sort-up\"></i>"
    end
  end

  @doc """
  Replaces accented letters by their regular versions.
  Taken from https://stackoverflow.com/a/68724296

  iex> unaccent("Et Ça sera sa moitié.")
  "Et Ca sera sa moitie."
  iex> unaccent(nil)
  ""
  """
  @spec unaccent(nil | binary()) :: binary()
  def unaccent(nil), do: ""

  def unaccent(value) when is_binary(value) do
    ~r/\p{Mn}/u
    |> Regex.replace(value |> :unicode.characters_to_nfd_binary(), "")
    |> :unicode.characters_to_nfc_binary()
  end

  @doc """
  Returns the list of dataset filters available in the backoffice index page.
  Each filter has a `key` (used in query params), a `label` (displayed to user),
  and whether it's active when selected.
  """
  def dataset_filters do
    [
      %{key: "outdated", label: dgettext("backoffice", "Outdated")},
      %{key: "inactive", label: dgettext("backoffice", "Deleted")},
      %{key: "archived", label: dgettext("backoffice", "Archived")},
      %{key: "hidden", label: dgettext("backoffice", "Hidden datasets")},
      %{key: "not_compliant", label: dgettext("backoffice", "GTFS with fatal failure")},
      %{key: "licence_not_specified", label: dgettext("backoffice", "With licence unspecified")},
      %{key: "multi_gtfs", label: dgettext("backoffice", "With more than 1 GTFS")},
      %{key: "resource_not_available", label: dgettext("backoffice", "With a resource not available")},
      %{key: "resource_under_90_availability", label: dgettext("backoffice", "With a resource under 90% availability")}
    ]
  end

  def notification_subscription_contact(%DB.NotificationSubscription{contact: %DB.Contact{} = contact}) do
    "#{DB.Contact.display_name(contact)} — #{contact.job_title} (#{contact.organization})"
  end
end
