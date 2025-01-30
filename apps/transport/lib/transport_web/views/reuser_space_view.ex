defmodule TransportWeb.ReuserSpaceView do
  use TransportWeb, :view
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]

  @doc """
  Is the following dataset eligible for the data sharing pilot for this contact, member
  of various organizations?
  """
  @spec data_sharing_pilot?(DB.Dataset.t(), DB.Contact.t()) :: boolean()
  def data_sharing_pilot?(%DB.Dataset{} = dataset, %DB.Contact{} = contact) do
    eligible_dataset_type = dataset.type == "public-transit"
    has_dataset_tag = DB.Dataset.has_custom_tag?(dataset, config_value(:dataset_custom_tag))
    member_eligible_org = data_sharing_eligible_org(contact) |> Enum.count() == 1

    Enum.all?([eligible_dataset_type, has_dataset_tag, member_eligible_org])
  end

  def data_sharing_eligible_org(%DB.Contact{organizations: organizations}) do
    data_sharing_eligible_org(organizations)
  end

  def data_sharing_eligible_org(organizations) when is_list(organizations) do
    Enum.filter(organizations, &(&1.id in config_value(:eligible_datagouv_organization_ids)))
  end

  defp config_value(key) do
    Application.fetch_env!(:transport, :"data_sharing_pilot_#{key}")
  end
end
