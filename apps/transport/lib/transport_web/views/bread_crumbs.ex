defmodule TransportWeb.BreadCrumbs do
  use TransportWeb, :view

  def breadcrumbs(args) do
    IO.inspect(Enum.count(args))
    IO.inspect(Enum.at(args, 0))
    IO.inspect(Enum.at(args, 1))
    apply(__MODULE__, :crumbs, args)
    |> render_crumbs
  end

  def crumbs(conn, :espace_producteur) do
    [{dgettext("espace-producteurs", "Your producer space"), page_path(conn, :espace_producteur)}]
  end

  def crumbs(conn, :select_resource) do
    crumbs(conn, :espace_producteur) ++
    [{dgettext("espace-producteurs", "Sélectionner une resource"), page_path(conn, :espace_producteur)}]
  end

  def crumbs(conn, :new_resource) do
    crumbs(conn, :espace_producteur) ++
    [{dgettext("espace-producteurs", "Nouvelle ressource"), page_path(conn, :espace_producteur)}]
  end

  def crumbs(conn, :update_resource, _dataset_id) do
    crumbs(conn, :select_resource) ++
    [{dgettext("espace-producteurs", "Mettre à jour une ressource"), page_path(conn, :espace_producteur)}]
  end

  def render_crumbs(crumbs_element) do
    content_tag :div, class: "breadcrumbs" do
      render_crumbs_element(crumbs_element)
    end
  end

  def render_crumbs_element([{text, link}]) do
    content_tag(:li, link(text, to: link), class: "breadcrumbs-element")
  end

  def render_crumbs_element([head | tail]) do
    List.flatten([render_crumbs_element([head]), render_crumbs_element(tail)])
  end
end
