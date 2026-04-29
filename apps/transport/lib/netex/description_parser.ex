defmodule Transport.NeTEx.DescriptionParser do
  @moduledoc """
  Extract network informations.
  """

  @behaviour Saxy.Handler

  import Transport.NeTEx.SaxyHelpers

  @empty %{
    networks: [],
    transport_modes: [],
    lines: 0,
    quays: 0,
    stop_places: 0,
    features: %{
      networks: false,
      stops: false,
      timetables: false,
      fares: false,
      parkings: false,
      accessibility: false
    }
  }

  def initial_state do
    capturing_initial_state(@empty)
  end

  def unwrap_result(final_state),
    do: final_state |> Map.take(Map.keys(@empty))

  def handle_event(:start_element, {element, _attributes}, state)
      when element in ["Network", "Line"] do
    {:ok, state |> push(element) |> start_capture()}
  end

  def handle_event(:start_element, {element, _attributes}, state)
      when state.capture do
    {:ok, state |> push(element)}
  end

  def handle_event(:end_element, "Network" = element, state) do
    {:ok, state |> stop_capture() |> end_element(element)}
  end

  def handle_event(:end_element, "Line" = element, state) do
    {:ok, state |> increment(:lines) |> stop_capture() |> end_element(element)}
  end

  def handle_event(:end_element, "Quay" = element, state) do
    {:ok, state |> increment(:quays) |> end_element(element)}
  end

  def handle_event(:end_element, "StopPlace" = element, state) do
    {:ok, state |> increment(:stop_places) |> end_element(element)}
  end

  def handle_event(:end_element, element, state) do
    {:ok, state |> end_element(element)}
  end

  def handle_event(:characters, chars, state)
      when state.capture and state.current_tree == ["Network", "Name"] do
    {:ok, state |> register_network(chars)}
  end

  def handle_event(:characters, chars, state)
      when state.capture and state.current_tree == ["Line", "TransportMode"] do
    {:ok, state |> register_transport_mode(chars)}
  end

  def handle_event(_, _, state), do: {:ok, state}

  defp end_element(state, element) do
    state |> feature_detection(element) |> pop()
  end

  defp register_network(state, network), do: update_in(state, [:networks], &(&1 ++ [network]))

  defp register_transport_mode(state, transport_mode),
    do: update_in(state, [:transport_modes], &(&1 ++ [transport_mode]))

  defp increment(state, key), do: update_in(state, [key], &(&1 + 1))

  @elements_per_feature %{
    :networks => [
      "Network",
      "GroupOfLines",
      "RoutingConstraintZone",
      "Line",
      "Direction",
      "Route",
      "RoutePoint",
      "PointOnRoute",
      "FlexibleLine",
      "FlexibleRoute",
      "DestinationDisplay",
      "FlexiblePointProperties",
      "ServiceJourneyPattern",
      "PointInJourneyPattern",
      "ScheduledStopPoint",
      "TimingPoint",
      "TransferRestriction",
      "PassengerStopAssignment",
      "FlexibleStopAssignment",
      "TrainStopAssignment",
      "SchematicMap"
    ],
    :stops => [
      "StopPlace",
      "FlexibleStopPlace",
      "Quay",
      "TopographicPlace",
      "StopPlaceEntrance",
      "Entrance",
      "AccessSpace"
    ],
    :timetables => [
      "ServiceJourney",
      "ServiceLink",
      "FlexibleServiceProperties",
      "TemplateServiceJourney",
      "HeadwayJourneyGroup",
      "RhythmicalJourneyGroup",
      "CoupledJourney",
      "JourneyPartCouple",
      "JourneyPart",
      "Train",
      "TrainComponent",
      "CompoundTrain",
      "TrainNumber",
      "TrainComponentLabelAssignment"
    ],
    :fares => [
      "FareZone",
      "FareStructureElement",
      "UserProfile",
      "DistributionChannel",
      "PreassignedFareProduct",
      "SaleDiscountRight",
      "UsageDiscountRight",
      "AmountOfPriceUnitProduct",
      "SalesOfferPackageElement",
      "SalesOfferPackage",
      "TypeOfTravelDocument",
      "TypeOfPricingRule",
      "DiscountingRule",
      "FareTable",
      "DistanceMatrixElement"
    ],
    :parkings => [
      "Parking",
      "ParkingBay"
    ],
    :accessibility => [
      "SitePathLink",
      "PathLink",
      "PathJunction",
      "NavigationPath",
      "FacilitySet",
      "PassengerEquipment",
      "PassengerSafetyEquipment",
      "SanitaryEquipment",
      "RubbishDisposalEquipment",
      "LuggageLockerEquipment",
      "TrolleyStandEquipment",
      "WaitingEquipment",
      "SeatingEquipment",
      "ShelterEquipment",
      "WaitingRoomEquipment",
      "AccessEquipment",
      "CrossingEquipment",
      "EntranceEquipment",
      "QueueingEquipment",
      "RampEquipment",
      "PlaceLighting",
      "RoughSurface",
      "StaircaseEquipment",
      "StairEnd",
      "StairFlight",
      "EscalatorEquipment",
      "TravelatorEquipment",
      "LiftEquipment",
      "SignEquipment",
      "HeadingSign",
      "GeneralSign",
      "PlaceSign",
      "TicketValidatorEquipment",
      "TicketingEquipment",
      "LocalService",
      "AssistanceService",
      "LuggageService",
      "CustomerService",
      "LostPropertyService",
      "MeetingPoint",
      "TicketingService",
      "HireService",
      "AccessibilityAssessment",
      "WheelchairAccess",
      "StepFreeAccess",
      "VisualSignsAvailable",
      "AudibleSignalsAvailable",
      "EscalatorFreeAccess",
      "LiftFreeAccess",
      "TactileGuidanceAvailable"
    ]
  }

  defp feature_detection(state, element_name) do
    @elements_per_feature
    |> Enum.reduce(state, fn {feature, element_names}, state ->
      if element_names |> Enum.member?(element_name) do
        state |> has(feature)
      else
        state
      end
    end)
  end

  defp has(state, feature), do: update_in(state, [:features, feature], fn _ -> true end)
end
