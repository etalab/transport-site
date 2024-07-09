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

  def crumbs(conn, :espace_producteur) do
    [{dgettext("espace-producteurs", "Your producer space"), page_path(conn, :espace_producteur)}]
  end

  def crumbs(conn, :reuser_space) do
    [{dgettext("reuser-space", "Reuser space"), reuser_space_path(conn, :espace_reutilisateur)}]
  end

  def crumbs(conn, :new_resource) do
    crumbs(conn, :espace_producteur) ++
      [
        {dgettext("espace-producteurs", "New resource"), nil}
      ]
  end

  def crumbs(conn, :contacts) do
    [{"Contacts", backoffice_contact_path(conn, :index)}]
  end

  def crumbs(conn, :contacts_edit) do
    crumbs(conn, :contacts) ++ [{"Créer/éditer un contact", nil}]
  end

  def crumbs(conn, :proxy_statistics) do
    crumbs(conn, :espace_producteur) ++
      [
        {dgettext("espace-producteurs", "Transport proxy statistics"), espace_producteur_path(conn, :proxy_statistics)}
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

  def crumbs(conn, :delete_resource, id) do
    # Same than below, can’t really link to edit dataset page
    crumbs(conn, :espace_producteur) ++
      [
        {dgettext("espace-producteurs", "Delete a resource"), nil}
      ]
  end

  def crumbs(conn, :update_resource) do
    # Ideally this should link to the edit_dataset crumb instead of the espace_producteur
    # but on the update resource page, we don’t have the DB dataset, but a datagouv API dataset
    # So can’t have reliably the same title and DB id than on the dataset edit page
    crumbs(conn, :espace_producteur) ++
      [
        {dgettext("espace-producteurs", "Update a resource"), nil}
      ]
  end

  def crumbs(conn, :datasets_edit, dataset_custom_title) do
    crumbs(conn, :reuser_space) ++ [{dataset_custom_title, nil}]
  end

  def crumbs(conn, :edit_dataset, dataset_custom_title, id) do
    crumbs(conn, :espace_producteur) ++ [{dataset_custom_title, espace_producteur_path(conn, :edit_dataset, id)}]
  end

  def render_crumbs(crumbs_element) do
    content_tag :div, class: "breadcrumbs" do
      render_crumbs_elements(crumbs_element)
    end
  end

  def render_crumb_element({text, link}, :list_element) do
    content_tag(:li, link(text, to: link), class: "breadcrumbs-element")
  end

  # last element does not need a link
  def render_crumb_element({text, _link}, :last_element) do
    content_tag(:li, text, class: "breadcrumbs-element")
  end

  def render_crumbs_elements([element]) do
    [render_crumb_element(element, :last_element)]
  end

  def render_crumbs_elements([head | tail]) do
    List.flatten([render_crumb_element(head, :list_element), render_crumbs_elements(tail)])
  end
end
