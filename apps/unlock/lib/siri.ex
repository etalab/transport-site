defmodule Unlock.SIRI do
  @moduledoc """
  All the SIRI XML management functions are grouped here at this point.
  """

  @doc """
  iex> Unlock.SIRI.parse_incoming("<elem attr='value'>text</elem>")
  {"elem", [{"attr", "value"}], ["text"]}
  """
  def parse_incoming(body) do
    {:ok, parsed_request} = Saxy.SimpleForm.parse_string(body, cdata_as_characters: false)
    parsed_request
  end

  defmodule RequestorRefReplacer do
    @doc """
    Newline must not cause a crash:
    iex> Unlock.SIRI.RequestorRefReplacer.replace_requestor_ref("<root>\u0044<hello></root>", %{new_requestor_ref: "ok"})
    "<root>\u0044<hello></root>"
    """

    def replace_requestor_ref(data, config) do
      case data do
        a = {tag, attributes, [some_text]} when is_binary(some_text) ->
          [last | _] = tag |> String.split(":") |> Enum.reverse()

          if last == "RequestorRef" do
            # TODO: add check & stop processing if incorrect requestor ref is detected
            {tag, attributes, [config.after]}
          else
            a
          end

        {tag, attributes, children} ->
          {
            tag,
            attributes,
            children |> Enum.map(&replace_requestor_ref(&1, config))
          }

        data when is_binary(data) ->
          data
      end
    end
  end
end
