defmodule TransportWeb.BreadCrumbs do
  @moduledoc """
  A module for creating breadcrumbs
  """
  use TransportWeb, :view

  def breadcrumbs(args) do
    __MODULE__
    |> apply(:crumbs, args)
    |> render_crumbs
  end

  def crumbs(_conn, :espace_producteur) do
    [{dgettext("espace-producteurs", "Producer space"), ~p"/espace_producteur"}]
  end

  def crumbs(_conn, :reuser_space) do
    [{dgettext("reuser-space", "Reuser space"), ~p"/espace_reutilisateur"}]
  end

  def crumbs(conn, :settings) do
    crumbs(conn, :reuser_space) ++ [{dgettext("reuser-space", "Settings"), ~p"/espace_reutilisateur/settings"}]
  end

  def crumbs(conn, :new_token) do
    crumbs(conn, :settings) ++ [{dgettext("reuser-space", "Create a new token"), nil}]
  end

  def crumbs(_conn, :contacts) do
    [{"Contacts", ~p"/backoffice/contacts"}]
  end

  def crumbs(conn, :contacts_edit) do
    crumbs(conn, :contacts) ++ [{"Créer/éditer un contact", nil}]
  end

  def crumbs(conn, :proxy_statistics) do
    crumbs(conn, :espace_producteur) ++
      [
        {dgettext("espace-producteurs", "Transport proxy statistics"), ~p"/espace_producteur/proxy_statistics"}
      ]
  end

  def crumbs(conn, :download_statistics) do
    crumbs(conn, :espace_producteur) ++
      [
        {dgettext("espace-producteurs", "Download statistics"), ~p"/espace_producteur/download_statistics"}
      ]
  end

  def crumbs(conn, :unanswered_discussions) do
    crumbs(conn, :espace_producteur) ++
      [
        {dgettext("espace-producteurs", "Unanswered discussions"), ~p"/espace_producteur/discussions"}
      ]
  end

  def crumbs(conn, :espace_producteur_notifications) do
    crumbs(conn, :espace_producteur) ++
      [
        {dgettext("espace-producteurs", "Notifications settings"), nil}
      ]
  end

  def crumbs(conn, :reuser_space_notifications) do
    crumbs(conn, :reuser_space) ++
      [
        {dgettext("espace-producteurs", "Notifications settings"), nil}
      ]
  end

  def crumbs(conn, :datasets_edit, dataset_custom_title) do
    crumbs(conn, :reuser_space) ++ [{dataset_custom_title, nil}]
  end

  def crumbs(conn, :edit_dataset, dataset_custom_title, id) do
    crumbs(conn, :espace_producteur) ++ [{dataset_custom_title, ~p"/espace_producteur/datasets/#{id}/edit"}]
  end

  def crumbs(conn, :delete_resource, dataset_custom_title, id) do
    crumbs(conn, :edit_dataset, dataset_custom_title, id) ++
      [{dgettext("espace-producteurs", "Delete a resource"), nil}]
  end

  def crumbs(conn, :new_resource, dataset_custom_title, id) do
    crumbs(conn, :edit_dataset, dataset_custom_title, id) ++
      [{dgettext("espace-producteurs", "New resource"), nil}]
  end

  def crumbs(conn, :update_resource, dataset_custom_title, id) do
    crumbs(conn, :edit_dataset, dataset_custom_title, id) ++
      [{dgettext("espace-producteurs", "Update a resource"), nil}]
  end

  def crumbs(conn, :reuser_improved_data, dataset_custom_title, id, resource_title) do
    crumbs(conn, :edit_dataset, dataset_custom_title, id) ++
      [{resource_title, nil}]
  end

  # The last element does not need a link
  def render_crumbs(crumbs) do
    assigns = %{links: Enum.drop(crumbs, -1), last: List.last(crumbs)}

    ~H"""
    <div class="breadcrumbs">
      <li :for={{text, link} <- @links} class="breadcrumbs-element"><.link href={link}>{text}</.link></li>
      <li class="breadcrumbs-element">{elem(@last, 0)}</li>
    </div>
    """
  end
end
