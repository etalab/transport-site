defmodule TransportWeb.Backoffice.ContactView do
  use TransportWeb, :view
  import Shared.DateTimeDisplay, only: [format_datetime_to_paris: 2]
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]
  import TransportWeb.Backoffice.PageView, only: [unaccent: 1]
  alias TransportWeb.PaginationHelpers

  def pagination_links(conn, contacts) do
    kwargs = [path: &backoffice_contact_path/3] |> add_filter(conn.params)

    PaginationHelpers.pagination_links(conn, contacts, kwargs)
  end

  @spec role_class(DB.Notification.t() | DB.NotificationSubscription.t()) :: binary()
  defp role_class(%{role: :producer}), do: "label"
  defp role_class(%{role: :reuser}), do: "label label--inactive"

  defp dataset_title(%DB.Dataset{custom_title: custom_title, type: type, is_hidden: false}) do
    "#{custom_title} (#{type})"
  end

  defp dataset_title(%DB.Dataset{custom_title: custom_title, type: type, is_hidden: true}) do
    "#{custom_title} (#{type}) — masqué"
  end

  defp notification_subscriptions_with_dataset(records) do
    records
    |> Enum.reject(&is_nil(&1.dataset_id))
    |> Enum.sort_by(&{&1.dataset.custom_title, &1.reason})
    |> Enum.group_by(& &1.dataset)
  end

  defp notification_subscriptions_without_dataset(records) do
    records
    |> Enum.filter(&is_nil(&1.dataset_id))
    |> Enum.sort_by(& &1.reason)
  end

  @spec add_filter(list, map) :: list
  defp add_filter(kwargs, params) do
    params
    |> Map.take(["q"])
    |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
    |> Enum.concat(kwargs)
  end
end
