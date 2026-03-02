defmodule Transport.NeTEx.TypesOfFrameStreamingParser do
  @moduledoc """
  Saxy streaming parser to extract type of frames from a given NeTEx file.
  """

  @behaviour Saxy.Handler

  import Transport.NeTEx.NeTExHelpers
  import Transport.NeTEx.SaxyHelpers

  def initial_state do
    %{
      types_of_frames: []
    }
  end

  def unwrap_result(final_state), do: final_state.types_of_frames

  def handle_event(:start_element, {"TypeOfFrameRef", attributes}, state) do
    ref = get_attribute!(attributes, "ref")

    {:ok, state |> register_type_of_frame(ref)}
  end

  def handle_event(_, _, state), do: {:ok, state}

  defp register_type_of_frame(state, ref) do
    case parse_type_of_frame(ref) do
      {:ok, frame} -> update_in(state, [:types_of_frames], &(&1 ++ [frame]))
      _ -> state
    end
  end
end
