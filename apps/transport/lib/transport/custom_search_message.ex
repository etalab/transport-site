defmodule Transport.CustomSearchMessage do
  @moduledoc """
  Some specific dataset search results have a custom text displayed.
  See for example https://transport.data.gouv.fr/datasets?type=public-transit&filter=has_realtime
  This module loads the custom message content from priv/search_custom_messages.yml
  """

  # loading happens at compile time
  @messages :transport
            |> Application.app_dir("priv")
            |> Kernel.<>("/search_custom_messages.yml")
            |> File.read!()
            |> YamlElixir.read_from_string!()

  def get_messages, do: @messages

  @doc """
  Given a query parameters and a locale, returns the custom message content
  """
  @spec get_message(map(), binary()) :: binary() | nil
  def get_message(query_params, locale) do
    get_messages() |> filter_messages(query_params, locale)
  end

  @spec filter_messages(list(), map(), binary()) :: binary() | nil
  def filter_messages(messages, query_params, locale) do
    messages
    |> Enum.find(&message_matches_query?(query_params, &1))
    |> case do
      %{"msg" => %{^locale => msg_content}} -> msg_content
      _ -> nil
    end
  end

  @doc """
  we have found a message matching a query if all the message search parameters are in the query.

  iex> Transport.CustomSearchMessage.message_matches_query?(%{"type" => "bus", "locale" => "en"}, %{"search_params" => [%{"key" => "type", "value" => "bus"}]})
  true
  iex> Transport.CustomSearchMessage.message_matches_query?(%{"type" => "bus", "locale" => "en"}, %{"search_params" => [%{"key" => "type", "value" => "bus"}, %{"key" => "modes", "value" => "xxx"}]})
  false
  """
  def message_matches_query?(query_params, %{"search_params" => message_search_params} = _messages) do
    message_search_params
    |> Enum.all?(fn %{"key" => msg_key, "value" => msg_value} ->
      case Map.fetch(query_params, msg_key) do
        {:ok, query_value} -> query_value == msg_value
        :error -> false
      end
    end)
  end
end
