defmodule TransportWeb.Backoffice.PageView do
  use TransportWeb, :view
  use Phoenix.Component
  alias DB.Dataset
  alias Plug.Conn.Query

  attr(:conn, Plug.Conn, required: true)
  attr(:field, :atom, required: true, doc: "the field to sort by")
  attr(:order_by, :map, required: true, doc: "the current order, as `%{field: atom, direction: atom}`")
  slot(:inner_block, required: true)

  def sort_link(assigns) do
    ~H"""
    <.link href={sort_url(@conn, @field, @order_by)}>
      {render_slot(@inner_block)} <i class={["sort-icon fa", sort_icon(@field, @order_by)]}></i>
    </.link>
    """
  end

  defp sort_url(conn, field, order_by) do
    params =
      conn.query_params
      |> Map.put("order_by", field)
      |> Map.put("dir", sort_direction(field, order_by))

    conn.request_path
    |> URI.parse()
    |> Map.put(:query, Query.encode(params))
    |> URI.to_string()
    |> Kernel.<>("#backoffice-datasets-table")
  end

  defp sort_direction(field, %{field: field, direction: :asc}), do: :desc
  defp sort_direction(_field, _order_by), do: :asc

  defp sort_icon(field, %{field: field, direction: :asc}), do: "fa-sort-down"
  defp sort_icon(field, %{field: field, direction: :desc}), do: "fa-sort-up"
  defp sort_icon(_field, _order_by), do: "fa-sort"

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
  Options of a datalist, as `{item, label}`: each item with its label, and again with
  the unaccented label when it differs, so that typing without accents also suggests it.

  iex> datalist_options(["Lyon", "Montréal"])
  [{"Lyon", "Lyon"}, {"Montréal", "Montréal"}, {"Montréal", "Montreal"}]
  iex> datalist_options([%{id: 1, name: "Élise"}], & &1.name)
  [{%{id: 1, name: "Élise"}, "Élise"}, {%{id: 1, name: "Élise"}, "Elise"}]
  """
  @spec datalist_options([item], (item -> binary())) :: [{item, binary()}] when item: any()
  def datalist_options(items, label_fun \\ & &1) do
    for item <- items, label <- with_unaccented(label_fun.(item)), do: {item, label}
  end

  defp with_unaccented(label), do: Enum.uniq([label, unaccent(label)])

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
