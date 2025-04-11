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

  def crumbs(conn, :settings) do
    crumbs(conn, :reuser_space) ++ [{dgettext("reuser-space", "Settings"), reuser_space_path(conn, :settings)}]
  end

  def crumbs(conn, :new_token) do
    crumbs(conn, :settings) ++ [{dgettext("reuser-space", "Create a new token"), nil}]
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

  def crumbs(conn, :datasets_edit, dataset_custom_title) do
    crumbs(conn, :reuser_space) ++ [{dataset_custom_title, nil}]
  end

  def crumbs(conn, :edit_dataset, dataset_custom_title, id) do
    crumbs(conn, :espace_producteur) ++ [{dataset_custom_title, espace_producteur_path(conn, :edit_dataset, id)}]
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
