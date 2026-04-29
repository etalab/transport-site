defmodule Transport.NeTEx.ToGeoJSON.ServiceLinkParser do
  @moduledoc """
  A SAX streaming XML parser for extracting ServiceLink elements from NeTEx files.

  ServiceLinks represent path segments between stops, typically containing
  a LineString geometry for the route path.

  This parser extracts: id, name, from_point_ref, to_point_ref, coordinates (LineString).
  """

  @behaviour Saxy.Handler

  alias Transport.NeTEx.ToGeoJSON.Coordinates

  @doc """
  Parses XML content and extracts all ServiceLink elements.

  ## Examples

      iex> xml = "<ServiceLink id=\\"link_1\\"><Name>Route A</Name></ServiceLink>"
      iex> {:ok, links} = ServiceLinkParser.parse(xml)
      iex> links
      [%{id: "link_1", name: "Route A"}]

  """
  @spec parse(String.t()) :: {:ok, [map()]} | {:error, String.t()}
  def parse(xml) when is_binary(xml) do
    initial_state = initial_state()

    case Saxy.parse_string(xml, __MODULE__, initial_state) do
      {:ok, state} -> {:ok, state.service_links}
      {:error, exception} -> {:error, Exception.message(exception)}
      {:halt, _state, _rest} -> {:error, "SAX parsing interrupted unexpectedly."}
    end
  end

  @doc """
  Parses XML from a stream and extracts all ServiceLink elements.
  """
  @spec parse_stream(Enumerable.t()) :: {:ok, [map()]} | {:error, String.t()}
  def parse_stream(stream) do
    initial_state = initial_state()

    stream
    |> Stream.map(&IO.iodata_to_binary/1)
    |> Saxy.parse_stream(__MODULE__, initial_state)
    |> case do
      {:ok, state} -> {:ok, state.service_links}
      {:error, exception} -> {:error, Exception.message(exception)}
      {:halt, _state, _rest} -> {:error, "SAX parsing interrupted unexpectedly."}
    end
  end

  defp initial_state do
    %{
      capture: false,
      current_tree: [],
      current_link: nil,
      service_links: [],
      # Buffer for accumulating character data
      char_buffer: ""
    }
  end

  # Start capturing when we encounter a ServiceLink element
  @impl Saxy.Handler
  def handle_event(:start_element, {"ServiceLink" = element, attributes}, state) do
    id = get_attribute(attributes, "id")

    {:ok,
     %{
       state
       | current_link: %{id: id},
         capture: true,
         current_tree: [element],
         char_buffer: ""
     }}
  end

  # Track nested elements while capturing
  def handle_event(:start_element, {element, attributes}, %{capture: true} = state) do
    state = %{state | current_tree: state.current_tree ++ [element], char_buffer: ""}

    # Capture ref attributes from FromPointRef and ToPointRef
    state =
      case state.current_tree do
        ["ServiceLink", "FromPointRef"] ->
          ref = get_attribute(attributes, "ref")
          %{state | current_link: Map.put(state.current_link, :from_point_ref, ref)}

        ["ServiceLink", "ToPointRef"] ->
          ref = get_attribute(attributes, "ref")
          %{state | current_link: Map.put(state.current_link, :to_point_ref, ref)}

        _ ->
          state
      end

    {:ok, state}
  end

  # End of ServiceLink element - save the link
  def handle_event(:end_element, "ServiceLink", state) do
    service_links =
      if state.current_link do
        state.service_links ++ [state.current_link]
      else
        state.service_links
      end

    {:ok, %{state | current_link: nil, capture: false, current_tree: [], service_links: service_links}}
  end

  # End of posList - parse coordinates (handles both gml:posList and posList)
  def handle_event(:end_element, element, %{capture: true} = state)
      when element in ["posList", "gml:posList"] do
    state = process_pos_list(state)
    {:ok, %{state | current_tree: state.current_tree |> List.delete_at(-1), char_buffer: ""}}
  end

  # End of coordinates element - parse coordinates (handles both gml:coordinates and coordinates)
  def handle_event(:end_element, element, %{capture: true} = state)
      when element in ["coordinates", "gml:coordinates"] do
    state = process_gml_coordinates(state)
    {:ok, %{state | current_tree: state.current_tree |> List.delete_at(-1), char_buffer: ""}}
  end

  # End of Name element - save name
  def handle_event(:end_element, "Name", %{current_tree: ["ServiceLink", "Name"]} = state) do
    current_link = Map.put(state.current_link, :name, String.trim(state.char_buffer))
    {:ok, %{state | current_link: current_link, current_tree: ["ServiceLink"], char_buffer: ""}}
  end

  # End of nested element
  def handle_event(:end_element, _element, %{capture: true} = state) do
    {:ok, %{state | current_tree: state.current_tree |> List.delete_at(-1)}}
  end

  # Accumulate characters (they might come in multiple events)
  def handle_event(:characters, chars, %{capture: true} = state) do
    {:ok, %{state | char_buffer: state.char_buffer <> chars}}
  end

  # Catch-all for unhandled events
  def handle_event(_, _, state), do: {:ok, state}

  defp process_pos_list(state) do
    case Coordinates.parse_gml_pos_list(state.char_buffer) do
      {:ok, coords} when length(coords) >= 2 ->
        %{state | current_link: Map.put(state.current_link, :coordinates, coords)}

      _ ->
        state
    end
  end

  defp process_gml_coordinates(state) do
    case Coordinates.parse_gml_coordinates(state.char_buffer) do
      {:ok, coords} when length(coords) >= 2 ->
        %{state | current_link: Map.put(state.current_link, :coordinates, coords)}

      _ ->
        state
    end
  end

  defp get_attribute(attributes, name) do
    Enum.find_value(attributes, fn
      {^name, value} -> value
      _ -> nil
    end)
  end
end
