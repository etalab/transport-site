defmodule TransportWeb.EspaceProducteurView do
  use TransportWeb, :view
  use Phoenix.Component
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]

  @spec action_path(Plug.Conn.t()) :: any
  def action_path(%Plug.Conn{params: %{"resource_datagouv_id" => r_id}, assigns: %{dataset: dataset}} = conn),
    do: espace_producteur_path(conn, :post_file, dataset.datagouv_id, r_id)

  def action_path(%Plug.Conn{assigns: %{dataset: dataset}} = conn),
    do: espace_producteur_path(conn, :post_file, dataset.datagouv_id)

  def title(%Plug.Conn{params: %{"resource_datagouv_id" => _}}),
    do: dgettext("resource", "Resource modification")

  def title(_), do: dgettext("resource", "Add a new resource")

  def remote?(%{"filetype" => "remote"}), do: true
  def remote?(_), do: false

  def datagouv_resource_edit_url(dataset_id, resource_id),
    do:
      :transport
      |> Application.fetch_env!(:datagouvfr_site)
      |> Path.join("/fr/admin/dataset/#{dataset_id}/resource/#{resource_id}")

  def datagouv_resource_creation_url(dataset_id),
    do:
      :transport
      |> Application.fetch_env!(:datagouvfr_site)
      |> Path.join("/fr/admin/dataset/#{dataset_id}?new_resource=")
end
