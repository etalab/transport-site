defmodule TransportWeb.EmailView do
  use TransportWeb, :view

  def link_for_dataset_section(%DB.Dataset{} = dataset, :discussion) do
    link_for_dataset(dataset, "#dataset-discussions")
  end

  def link_for_dataset(%DB.Dataset{slug: slug, custom_title: custom_title}, anchor \\ "") do
    assigns = %{url: url(~p"/datasets/#{slug}") <> anchor, title: custom_title}
    ~H|<.link href={@url}>{@title}</.link>|
  end

  def link_for_dataset_discussions(%DB.Dataset{slug: slug}) do
    assigns = %{url: url(~p"/datasets/#{slug}") <> "#dataset-discussions"}
    ~H|<.link href={@url}>l’espace de discussion du jeu de données</.link>|
  end

  def link_for_dataset_with_type(%DB.Dataset{type: type} = dataset) do
    assigns = %{link: link_for_dataset(dataset), type: DB.Dataset.type_to_str(type)}
    ~H|{@link} - ({@type})|
  end

  def link_for_resource(%DB.Resource{id: id, title: title}) do
    assigns = %{url: url(~p"/resources/#{id}"), title: title}
    ~H|<.link href={@url}>{@title}</.link>|
  end

  def link_for_espace_producteur(view_name) do
    params = [utm_source: "transactional_email", utm_medium: "email", utm_campaign: to_string(view_name)]
    assigns = %{url: url(~p"/espace_producteur?#{params}")}
    ~H|<.link href={@url}>Espace Producteur</.link>|
  end

  def link_for_reuser_space(view_name) do
    params = [utm_source: "transactional_email", utm_medium: "email", utm_campaign: to_string(view_name)]
    assigns = %{url: url(~p"/espace_reutilisateur?#{params}")}
    ~H|<.link href={@url}>Espace réutilisateur</.link>|
  end

  def link_for_login do
    assigns = %{url: url(~p"/login/explanation?#{[redirect_path: "/"]}")}
    ~H|<.link href={@url}>vous reconnecter</.link>|
  end
end
