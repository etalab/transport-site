defmodule TransportWeb.EmailView do
  use TransportWeb, :view

  def link_for_dataset(%DB.Dataset{slug: slug, custom_title: custom_title}, mode) when mode in [:heex, :markdown] do
    url = TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)

    case mode do
      :markdown -> "[#{custom_title}](#{url})"
      :heex -> link(custom_title, to: url)
    end
  end
end
