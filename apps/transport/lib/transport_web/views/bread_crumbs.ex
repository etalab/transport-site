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

  def crumbs(conn, :new_resource) do
    crumbs(conn, :espace_producteur) ++
    [{dgettext("espace-producteurs", "Nouvelle ressource"), page_path(conn, :espace_producteur)}]
  end

  def crumbs(conn, :select_resource, id) do
    crumbs(conn, :espace_producteur) ++
    [{dgettext("espace-producteurs", "Sélectionner une resource"), resource_path(conn, :resources_list, id)}]
  end

  def crumbs(conn, :update_resource, id) do
    crumbs(conn, :select_resource, id) ++
    [{dgettext("espace-producteurs", "Mettre à jour une ressource"), page_path(conn, :espace_producteur)}]
  end

  def render_crumbs(crumbs_element) do
    content_tag :div, class: "breadcrumbs" do
      render_crumbs_elements_list(crumbs_element)
    end
  end

  def render_crumbs_element({text, link}, :list_element) do
    content_tag(:li, link(text, to: link), class: "breadcrumbs-element")
  end

  # last element does not need a link
  def render_crumbs_element({text, _link}, :last_element) do
    content_tag(:li, text, class: "breadcrumbs-element")
  end

  def render_crumbs_elements_list([element]) do
    [render_crumbs_element(element, :last_element)]
  end

  def render_crumbs_elements_list([head | tail]) do
    List.flatten([render_crumbs_element(head, :list_element), render_crumbs_elements_list(tail)])
  end
end
