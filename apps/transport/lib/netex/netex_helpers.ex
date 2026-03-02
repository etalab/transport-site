defmodule Transport.NeTEx.NeTExHelpers do
  @moduledoc """
  Helpers related to NeTEx format.
  """

  @common_frame "NETEX_COMMUN"
  @stop_frame "NETEX_ARRET"
  @line_frame "NETEX_LIGNE"
  @network_frame "NETEX_RESEAU"
  @timetable_frame "NETEX_HORAIRE"
  @calendar_frame "NETEX_CALENDRIER"
  @fares_frame "NETEX_TARIF"
  @france_frame "NETEX_FRANCE"
  @n_line_frame "NETEX_N_LIGNE"
  @parking_frame "NETEX_PARKING"
  @accessibility_frame "NETEX_ACCESSIBILITE"

  @valid_type_of_frames [
    # for GeneralFrame
    @common_frame,
    @stop_frame,
    @line_frame,
    @network_frame,
    @timetable_frame,
    @calendar_frame,
    @fares_frame,
    @parking_frame,
    @accessibility_frame,
    # for CompositeFrame
    @france_frame,
    @n_line_frame
  ]

  @doc """
  Strict parser of TypeOfFrameRef compatible with the French Profile.
  Non standard types are discarded.
  """
  def parse_type_of_frame(type_of_frame) do
    case type_of_frame |> String.split(":") |> Enum.take(3) do
      [_prefix, "TypeOfFrame", sub_profile] when sub_profile in @valid_type_of_frames ->
        {:ok, sub_profile}

      _ ->
        :error
    end
  end

  def calendar_frame?(type_of_frame) do
    parse_type_of_frame(type_of_frame) == {:ok, @calendar_frame}
  end
end
