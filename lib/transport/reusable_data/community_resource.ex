defmodule Transport.ReusableData.CommunityResource do
  @moduledoc """
  Represents a community resource, for example a dataset improvement, as it is
  published by a reuser.
  """

  alias Transport.ReusableData.Organization
  defstruct [:id, :title, :description, :url, :organization]
  use ExConstructor

  @type t :: %__MODULE__{
    id:           String.t,
    title:        String.t,
    description:  String.t,
    url:          String.t,
    organization: %Organization{}
  }

  @doc """
  Add an organization

  ## Examples

      iex> %{title: "Resource"}
      ...> |> CommunityResource.new
      ...> |> CommunityResource.assign(:organization)
      ...> |> Map.get(:organization)
      ...> |> Map.get(:name)
      nil

      iex> %{title: "Resource", organization: nil}
      ...> |> CommunityResource.new
      ...> |> CommunityResource.assign(:organization)
      ...> |> Map.get(:organization)
      ...> |> Map.get(:name)
      nil

      iex> %{:title => "Resource", :organization => %{name: "OSM"}}
      ...> |> CommunityResource.new
      ...> |> CommunityResource.assign(:organization)
      ...> |> Map.get(:organization)
      ...> |> Map.get(:name)
      "OSM"

  """
  @spec assign(%__MODULE__{}, :organization) :: %__MODULE__{}
  def assign(%__MODULE__{} = resource, :organization) do
    organization =
      resource
      |> Map.get(:organization)
      |> case do
        nil -> %{}
        any -> any
      end
      |> Organization.new

    new(%{resource | organization: organization})
  end
end
