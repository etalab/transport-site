defmodule Transport.NeTEx.FrenchProfile do
  @moduledoc """
  Definition of the validation rules for the French NeTEx profile.

  This definition is still work in progress. It's versionned to track progress
  and adapt any relevant user interface.

  According to <https://bitbucket.org/enroute-mobi/netex/src/8099b6ebb4327f32cbc1f266099d966fcafbb761/lib/netex/source.rb#lines-219>,
  only a subset of the NeTEx specification can be validated by enRoute.
  """

  alias Transport.NeTEx.FrenchProfile.V1
  alias Transport.NeTEx.FrenchProfile.V2

  @versions [V1, V2]

  def resolve(slug) do
    Enum.find(@versions, fn module -> module.slug() == slug end)
  end

  defdelegate slug, to: V2
  defdelegate ruleset(device), to: V2
  defdelegate markdown(device), to: V2
end
