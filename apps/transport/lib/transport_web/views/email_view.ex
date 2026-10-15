defmodule TransportWeb.EmailView do
  use TransportWeb, :view

  def link_for_dataset_section(%DB.Dataset{} = dataset, :discussion) do
    link_for_dataset(dataset, "#dataset-discussions")
  end

  def link_for_dataset(%DB.Dataset{slug: slug, custom_title: custom_title}, anchor \\ "") do
    link_html(custom_title, url(~p"/datasets/#{slug}") <> anchor)
  end

  def link_for_dataset_discussions(%DB.Dataset{slug: slug}) do
    link_html("l’espace de discussion du jeu de données", url(~p"/datasets/#{slug}") <> "#dataset-discussions")
  end

  def link_for_dataset_with_type(%DB.Dataset{type: type} = dataset) do
    link = link_for_dataset(dataset) |> Phoenix.HTML.safe_to_string()
    Phoenix.HTML.raw(link <> " - (#{DB.Dataset.type_to_str(type)})")
  end

  def link_for_resource(%DB.Resource{id: id, title: title}) do
    link_html(title, url(~p"/resources/#{id}"))
  end

  def link_for_espace_producteur(view_name) do
    params = [utm_source: "transactional_email", utm_medium: "email", utm_campaign: to_string(view_name)]
    link_html("Espace Producteur", url(~p"/espace_producteur?#{params}"))
  end

  def link_for_reuser_space(view_name) do
    params = [utm_source: "transactional_email", utm_medium: "email", utm_campaign: to_string(view_name)]
    link_html("Espace réutilisateur", url(~p"/espace_reutilisateur?#{params}"))
  end

  def link_for_login do
    link_html("vous reconnecter", url(~p"/login/explanation?#{[redirect_path: "/"]}"))
  end
end
