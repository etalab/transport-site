defmodule Transport.NeTEx.FrenchProfile do
  @moduledoc """
  Definition of the validation rules for the French NeTEx profile.

  This definition is still work in progress. It's versionned to track progress
  and adapt any relevant user interface.

  According to <https://bitbucket.org/enroute-mobi/netex/src/8099b6ebb4327f32cbc1f266099d966fcafbb761/lib/netex/source.rb#lines-219>,
  only a subset of the NeTEx specification can be validated by enRoute.
  """

  import Transport.NeTEx.ChouetteValidRulesetGenerator

  def ruleset(device \\ :stdio) do
    definition() |> encode_ruleset(device)
  end

  def markdown(device \\ :stdio) do
    definition() |> document_ruleset(device)
  end

  defp definition do
    [elements_communs(), arrets(), parkings(), description_reseaux(), horaires(), accessibilite(), tarifs()]
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
        mandatory_attributes(
          "Point",
          ["Location"],
          "6.5 Attributs de Point",
          "https://normes.transport.data.gouv.fr/normes/netex/elements_communs/#attributs-de-point"
        ),
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

  def arrets do
    %{
      sub_profile: "stops",
      title: "Arrêts",
      ruleset: [
        mandatory_attributes(
          "SiteComponent",
          ["SiteRef"],
          "7.4.1 Attributs SiteComponent",
          "https://normes.transport.data.gouv.fr/normes/netex/arrets/#attributs-sitecomponent"
        )
      ]
    }
  end

  def parkings do
    %{
      sub_profile: "parkings",
      title: "Parkings",
      ruleset: [
        # Not supported by enRoute yet.
        # mandatory_attributes(
        #   "Parking",
        #   ["ParkingType", "ParkingLayout", "TotalCapacity"],
        #   "6.2.1 Parkings",
        #   "https://normes.transport.data.gouv.fr/normes/netex/parkings/#parking"
        # ),

        # Not supported by enRoute yet.
        # mandatory_attributes(
        #   "ParkingComponent",
        #   ["MaximumHeight"],
        #   "6.2.2 Composants des Parkings",
        #   "https://normes.transport.data.gouv.fr/normes/netex/parkings/#composants-des-parkings"
        # )
      ]
    }
  end

  def description_reseaux do
    %{
      sub_profile: "networks",
      title: "Description des réseaux",
      ruleset: [
        mandatory_attributes(
          "DestinationDisplay",
          ["FrontText"],
          "6.7 Les affichages de destination",
          "https://normes.transport.data.gouv.fr/normes/netex/reseaux/#les-affichages-de-destination"
        )

        # Not supported by enRoute yet.
        # mandatory_attributes(
        #   "DestinationDisplayVariant",
        #   ["FrontText"],
        #   "6.7.1 Les variantes d’affichages de destination",
        #   "https://normes.transport.data.gouv.fr/normes/netex/reseaux/#les-variantes-daffichages-de-destination"
        # ),

        # Not supported by enRoute yet.
        # mandatory_attributes(
        #   "TransferDuration",
        #   ["DefaultDuration"],
        #   "6.10.0.4 Transferts",
        #   "https://normes.transport.data.gouv.fr/normes/netex/reseaux/#transferts"
        # )
      ]
    }
  end

  def horaires do
    %{
      sub_profile: "timetables",
      title: "Horaires",
      ruleset: [
        # Not supported by enRoute yet.
        # mandatory_attributes(
        #   "InterchangeTimesGroup",
        #   ["StandardTransferTime"],
        #   "6.8 Les correspondances entre course",
        #   "https://normes.transport.data.gouv.fr/normes/netex/horaires/#les-correspondances-entre-course"
        # )
      ]
    }
  end

  def accessibilite do
    %{
      sub_profile: "accessibility",
      title: "Accessibilité",
      ruleset: [
        # Not supported by enRoute yet.
        # mandatory_attributes(
        #   "SitePathLink",
        #   ["Distance", "LineString"],
        #   "6.6 Les Cheminements",
        #   "https://normes.transport.data.gouv.fr/normes/netex/accessibilite/#les-cheminements"
        # )
      ]
    }
  end

  def tarifs do
    %{
      sub_profile: "fares",
      title: "Tarifs",
      ruleset: [
        # Not supported by enRoute yet.
        # mandatory_attributes(
        #   "TimeInterval",
        #   ["StartTime", "EndTime"],
        #   "6.4.4.1 Intervalle de temps (TimeInterval)",
        #   "https://normes.transport.data.gouv.fr/normes/netex/tarifs/#intervalle-de-temps-timeinterval"
        # )
      ]
    }
  end
end
