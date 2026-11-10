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

  def crumbs(:espace_producteur) do
    [{dgettext("espace-producteurs", "Producer space"), ~p"/espace_producteur"}]
  end

  def crumbs(:reuser_space) do
    [{dgettext("reuser-space", "Reuser space"), ~p"/espace_reutilisateur"}]
  end

  def crumbs(:settings) do
    crumbs(:reuser_space) ++ [{dgettext("reuser-space", "Settings"), ~p"/espace_reutilisateur/settings"}]
  end

  def crumbs(:new_token) do
    crumbs(:settings) ++ [{dgettext("reuser-space", "Create a new token"), nil}]
  end

  def crumbs(:contacts) do
    [{"Contacts", ~p"/backoffice/contacts"}]
  end

  def crumbs(:contacts_edit) do
    crumbs(:contacts) ++ [{"Créer/éditer un contact", nil}]
  end

  def crumbs(:proxy_statistics) do
    crumbs(:espace_producteur) ++
      [
        {dgettext("espace-producteurs", "Transport proxy statistics"), ~p"/espace_producteur/proxy_statistics"}
      ]
  end

  def crumbs(:download_statistics) do
    crumbs(:espace_producteur) ++
      [
        {dgettext("espace-producteurs", "Download statistics"), ~p"/espace_producteur/download_statistics"}
      ]
  end

  def crumbs(:unanswered_discussions) do
    crumbs(:espace_producteur) ++
      [
        {dgettext("espace-producteurs", "Unanswered discussions"), ~p"/espace_producteur/discussions"}
      ]
  end

  def crumbs(:espace_producteur_notifications) do
    crumbs(:espace_producteur) ++
      [
        {dgettext("espace-producteurs", "Notifications settings"), nil}
      ]
  end

  def crumbs(:reuser_space_notifications) do
    crumbs(:reuser_space) ++
      [
        {dgettext("espace-producteurs", "Notifications settings"), nil}
      ]
  end

  def crumbs(:datasets_edit, dataset_custom_title) do
    crumbs(:reuser_space) ++ [{dataset_custom_title, nil}]
  end

  def crumbs(:edit_dataset, dataset_custom_title, id) do
    crumbs(:espace_producteur) ++ [{dataset_custom_title, ~p"/espace_producteur/datasets/#{id}/edit"}]
  end

  def crumbs(:delete_resource, dataset_custom_title, id) do
    crumbs(:edit_dataset, dataset_custom_title, id) ++
      [{dgettext("espace-producteurs", "Delete a resource"), nil}]
  end

  def crumbs(:new_resource, dataset_custom_title, id) do
    crumbs(:edit_dataset, dataset_custom_title, id) ++
      [{dgettext("espace-producteurs", "New resource"), nil}]
  end

  def crumbs(:update_resource, dataset_custom_title, id) do
    crumbs(:edit_dataset, dataset_custom_title, id) ++
      [{dgettext("espace-producteurs", "Update a resource"), nil}]
  end

  def crumbs(:reuser_improved_data, dataset_custom_title, id, resource_title) do
    crumbs(:edit_dataset, dataset_custom_title, id) ++
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
