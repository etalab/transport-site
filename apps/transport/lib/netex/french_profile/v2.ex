defmodule Transport.NeTEx.FrenchProfile.V2 do
  @moduledoc """
  Definition of the validation rules for the French NeTEx profile.

  This definition is still work in progress. It's versionned to track progress
  and adapt any relevant user interface.

  According to <https://bitbucket.org/enroute-mobi/netex/src/8099b6ebb4327f32cbc1f266099d966fcafbb761/lib/netex/source.rb#lines-219>,
  only a subset of the NeTEx specification can be validated by enRoute.
  """

  import Transport.NeTEx.ChouetteValidRulesetGenerator

  alias Transport.NeTEx.FrenchProfile.V1, as: Previous

  def slug, do: "pan:french_profile:2"

  def ruleset(device \\ :stdio) do
    definition() |> encode_ruleset(device)
  end

  def markdown(device \\ :stdio, markdown_options \\ []) do
    definition() |> document_ruleset(device, markdown_options)
  end

  defp definition do
    [
      elements_communs(),
      Previous.arrets(),
      Previous.parkings(),
      Previous.description_reseaux(),
      Previous.horaires(),
      Previous.accessibilite(),
      Previous.tarifs()
    ]
  end

  def elements_communs do
    %{
      sub_profile: "commons",
      title: "Éléments communs",
      ruleset: [
        mandatory_attributes(
          "GroupOfEntity",
          ["Name"],
          "6.3 Attributs de GroupOfEntities",
          "https://normes.transport.data.gouv.fr/normes/netex/elements_communs/#attributs-de-groupofentities"
        ),
        # See <https://github.com/etalab/transport-profil-netex-fr/issues/34>:
        # this rule is misplaced and should not be considered for now. The
        # profile is expected to be amended accordingly.
        # mandatory_attributes(
        #   "Point",
        #   ["Location"],
        #   "6.5 Attributs de Point",
        #   "https://normes.transport.data.gouv.fr/normes/netex/elements_communs/#attributs-de-point"
        # ),
        mandatory_attributes(
          "Organisation",
          ["OrganisationType"],
          "6.18 Institutions",
          "https://normes.transport.data.gouv.fr/normes/netex/elements_communs/#institutions"
        )

        # Not supported by enRoute yet.
        # mandatory_attributes(
        #   "ServiceRequest",
        #   ["MessageIdentifier"],
        #   "8.2.2 Requête",
        #   "https://normes.transport.data.gouv.fr/normes/netex/elements_communs/#requ%C3%AAte"
        # ),

        # Not supported by enRoute yet.
        # mandatory_attributes(
        #   "ServiceDelivery",
        #   ["RequestMessageRef", "Status"],
        #   "8.2.3 Réponse",
        #   "https://normes.transport.data.gouv.fr/normes/netex/elements_communs/#r%C3%A9ponse"
        # ),

        # Not supported by enRoute yet.
        # mandatory_attributes(
        #   "DataObjectDelivery",
        #   ["RequestMessageRef", "Status"],
        #   "8.2.3 Réponse",
        #   "https://normes.transport.data.gouv.fr/normes/netex/elements_communs/#r%C3%A9ponse"
        # )
      ]
    }
  end
end
