defmodule TransportWeb.ReuserSpaceView do
  use TransportWeb, :view
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]

  def default_for_contact?(%DB.Token{id: token_id}, %DB.Contact{default_tokens: [%DB.Token{id: id}]}) do
    token_id == id
  end

  def default_for_contact?(%DB.Token{}, %DB.Contact{default_tokens: _}), do: false
end
