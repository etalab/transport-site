defmodule TransportWeb.EmailView do
  use TransportWeb, :view

  import TransportWeb.Router.Helpers,
    # Use only *_url helpers, not *_path as we need absolute URLs
    only: [
      dataset_url: 3,
      resource_url: 3,
      page_url: 3,
      reuser_space_url: 3
    ]

  def link_for_dataset_section(%DB.Dataset{} = dataset, :discussion) do
    link_for_dataset(dataset, "#dataset-discussions")
  end

  def link_for_dataset(%DB.Dataset{slug: slug, custom_title: custom_title}, anchor \\ "") do
    url = dataset_url(TransportWeb.Endpoint, :details, slug)
    link(custom_title, to: url <> anchor)
  end

  def link_for_dataset_discussions(%DB.Dataset{slug: slug}) do
    url = dataset_url(TransportWeb.Endpoint, :details, slug)
    link("l’espace de discussion du jeu de données", to: url <> "#dataset-discussions")
  end

  def link_for_dataset_with_type(%DB.Dataset{type: type} = dataset) do
    link = link_for_dataset(dataset) |> Phoenix.HTML.safe_to_string()
    Phoenix.HTML.raw(link <> " - (#{DB.Dataset.type_to_str(type)})")
  end

  def link_for_resource(%DB.Resource{id: id, title: title}) do
    url = resource_url(TransportWeb.Endpoint, :details, id)
    link(title, to: url)
  end

  def link_for_espace_producteur(view_name) do
    url =
      page_url(TransportWeb.Endpoint, :espace_producteur,
        utm_source: "transactional_email",
        utm_medium: "email",
        utm_campaign: to_string(view_name)
      )

    link("Espace Producteur", to: url)
  end

  def link_for_reuser_space(view_name) do
    url =
      reuser_space_url(TransportWeb.Endpoint, :espace_reutilisateur,
        utm_source: "transactional_email",
        utm_medium: "email",
        utm_campaign: to_string(view_name)
      )

    link("Espace réutilisateur", to: url)
  end

  def link_for_login do
    url = page_url(TransportWeb.Endpoint, :login, redirect_path: "/")

    link("vous reconnecter", to: url)
  end
end
