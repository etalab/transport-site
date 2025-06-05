defmodule TransportWeb.ReuserSpaceView do
  use TransportWeb, :view
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]

  def default_for_contact?(%DB.Token{id: token_id}, %DB.Contact{default_tokens: [%DB.Token{id: id}]}) do
    token_id == id
  end

  def default_for_contact?(%DB.Token{}, %DB.Contact{default_tokens: _}), do: false

  def eligible_for_tokens?(%Plug.Conn{assigns: %{contact: %DB.Contact{} = contact}} = conn) do
    eligible_org_ids = [
      # BlaBlaCar
      "5b9f70f18b4c4101942a27ff",
      # Futureco
      "655f8ef36a24e8d0522aa2a6"
    ]

    member_of_eligible_orgs = Enum.count(contact.organizations, &(&1.id in eligible_org_ids)) > 0
    TransportWeb.Session.admin?(conn) or member_of_eligible_orgs
  end
end
