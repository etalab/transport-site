defmodule Transport.NeTEx.ToGeoJSON.QuayParser do
  @moduledoc """
  A SAX streaming XML parser for extracting Quay elements from NeTEx files.

  Quays represent platforms or boarding positions within a StopPlace.
  This parser extracts: id, name, public_code, latitude, longitude.

  Similar structure to `Transport.NeTEx.StopPlacesStreamingParser` but for Quay elements.
  """

  @behaviour Saxy.Handler

  @doc """
  Parses XML content and extracts all Quay elements.

  ## Examples

      iex> xml = "<Quay id=\\"quay_1\\"><Name>Platform 1</Name></Quay>"
      iex> {:ok, quays} = QuayParser.parse(xml)
      iex> quays
      [%{id: "quay_1", name: "Platform 1"}]

  """
  @spec parse(String.t()) :: {:ok, [map()]} | {:error, String.t()}
  def parse(xml) when is_binary(xml) do
    initial_state = %{
      capture: false,
      current_tree: [],
      current_quay: nil,
      quays: []
    }

    case Saxy.parse_string(xml, __MODULE__, initial_state) do
      {:ok, state} -> {:ok, state.quays}
      {:error, exception} -> {:error, Exception.message(exception)}
      {:halt, _state, _rest} -> {:error, "SAX parsing interrupted unexpectedly."}
    end
  end

  @doc """
  Parses XML from a stream and extracts all Quay elements.
  """
  @spec parse_stream(Enumerable.t()) :: {:ok, [map()]} | {:error, String.t()}
  def parse_stream(stream) do
    initial_state = %{
      capture: false,
      current_tree: [],
      current_quay: nil,
      quays: []
    }

    stream
    |> Stream.map(&IO.iodata_to_binary/1)
    |> Saxy.parse_stream(__MODULE__, initial_state)
    |> case do
      {:ok, state} -> {:ok, state.quays}
      {:error, exception} -> {:error, Exception.message(exception)}
      {:halt, _state, _rest} -> {:error, "SAX parsing interrupted unexpectedly."}
    end
  end

  # Start capturing when we encounter a Quay element
  @impl Saxy.Handler
  def handle_event(:start_element, {"Quay" = element, attributes}, state) do
    id = get_attribute(attributes, "id")

    {:ok,
     %{
       state
       | current_quay: %{id: id, type: :quay},
         capture: true,
         current_tree: [element]
     }}
  end

  # Track nested elements while capturing
  def handle_event(:start_element, {element, _attributes}, %{capture: true} = state) do
    {:ok, %{state | current_tree: state.current_tree ++ [element]}}
  end

  # End of Quay element - save the quay
  def handle_event(:end_element, "Quay", state) do
    quays =
      if state.current_quay do
        state.quays ++ [state.current_quay]
      else
        state.quays
      end

    {:ok, %{state | current_quay: nil, capture: false, current_tree: [], quays: quays}}
  end

  # End of nested element
  def handle_event(:end_element, _element, %{capture: true} = state) do
    {:ok, %{state | current_tree: state.current_tree |> List.delete_at(-1)}}
  end

  # Parse Name
  def handle_event(:characters, chars, %{current_tree: ["Quay", "Name"]} = state) do
    {:ok, %{state | current_quay: Map.put(state.current_quay, :name, chars)}}
  end

  # Parse PublicCode
  def handle_event(:characters, chars, %{current_tree: ["Quay", "PublicCode"]} = state) do
    {:ok, %{state | current_quay: Map.put(state.current_quay, :public_code, chars)}}
  end

  # Parse Latitude
  def handle_event(
        :characters,
        chars,
        %{current_tree: ["Quay", "Centroid", "Location", "Latitude"]} = state
      ) do
    {:ok, %{state | current_quay: Map.put(state.current_quay, :latitude, parse_float!(chars))}}
  end

  # Parse Longitude
  def handle_event(
        :characters,
        chars,
        %{current_tree: ["Quay", "Centroid", "Location", "Longitude"]} = state
      ) do
    {:ok, %{state | current_quay: Map.put(state.current_quay, :longitude, parse_float!(chars))}}
  end

  # Catch-all for unhandled events
  def handle_event(_, _, state), do: {:ok, state}

  defp get_attribute(attributes, name) do
    Enum.find_value(attributes, fn
      {^name, value} -> value
      _ -> nil
    end)
  end

  defp parse_float!(binary) do
    {value, ""} = Float.parse(binary)
    value
  end
end
