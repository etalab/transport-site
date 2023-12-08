defmodule TransportWeb.EmailView do
  use TransportWeb, :view

  def link_for_dataset(%DB.Dataset{slug: slug, custom_title: custom_title}) do
    url = TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)
    link(custom_title, to: url)
  end

  def link_for_dataset_discussions(%DB.Dataset{slug: slug}) do
    url = TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)
    link("l’espace de discussion du jeu de données", to: url <> "#dataset-discussions")
  end

  def link_for_resource(%DB.Resource{id: id, title: title}) do
    url = TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :details, id)
    link(title, to: url)
  end
end
