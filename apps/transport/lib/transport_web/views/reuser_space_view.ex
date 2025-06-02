defmodule TransportWeb.ReuserSpaceView do
  use TransportWeb, :view
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]


  def default_for_contact?(%DB.Token{default_for_contact_id: default_for_contact_id}, %DB.Contact{id: contact_id}) do
    default_for_contact_id == contact_id
  end

  def eligible_for_tokens?(%Plug.Conn{assigns: %{contact: %DB.Contact{} = contact}} = conn) do
    eligible_org_ids = [
      # BlaBlaCar
      "5b9f70f18b4c4101942a27ff"
    ]

    member_of_eligible_orgs = Enum.count(contact.organizations, &(&1.id in eligible_org_ids)) > 0
    TransportWeb.Session.admin?(conn) or member_of_eligible_orgs
  end
end
