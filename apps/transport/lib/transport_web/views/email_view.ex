defmodule TransportWeb.EmailView do
  use TransportWeb, :view

  def link_for_dataset_section(%DB.Dataset{} = dataset, :discussion) do
    link_for_dataset(dataset, "#dataset-discussions")
  end

  def link_for_dataset(%DB.Dataset{slug: slug, custom_title: custom_title}, anchor \\ "") do
    url = TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)
    link(custom_title, to: url <> anchor)
  end

  def link_for_dataset_discussions(%DB.Dataset{slug: slug}) do
    url = TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)
    link("l’espace de discussion du jeu de données", to: url <> "#dataset-discussions")
  end

  def link_for_resource(%DB.Resource{id: id, title: title}) do
    url = TransportWeb.Router.Helpers.resource_url(TransportWeb.Endpoint, :details, id)
    link(title, to: url)
  end

  def link_for_espace_producteur(view_name) do
    url =
      TransportWeb.Router.Helpers.page_url(TransportWeb.Endpoint, :espace_producteur,
        utm_source: "transactional_email",
        utm_medium: "email",
        utm_campaign: to_string(view_name)
      )

    link("Espace Producteur", to: url)
  end
end
