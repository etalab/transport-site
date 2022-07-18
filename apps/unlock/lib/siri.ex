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
    @moduledoc """
    A module able to replace `RequestorRef` tags found in a
    [simple form](https://www.erlang.org/doc/man/xmerl.html#export_simple-3) xmerl document,
    all while returning the replaced values.
    """

    @doc """
    The `RequestorRef` inner value must be replaced, and the replaced ones must be returned for verification:

    iex> input = Unlock.SIRI.parse_incoming("<root><RequestorRef>before</RequestorRef></root>")
    iex> Unlock.SIRI.RequestorRefReplacer.replace_requestor_ref(input, "after")
    {
      {"root", [], [{"RequestorRef", [], ["after"]}]},
      ["before"]
    }

    The replacement must occur even if the tag is namespaced:

    iex> input = Unlock.SIRI.parse_incoming("<root><siri:RequestorRef>before</siri:RequestorRef></root>")
    iex> Unlock.SIRI.RequestorRefReplacer.replace_requestor_ref(input, "after")
    {
      {"root", [], [{"siri:RequestorRef", [], ["after"]}]},
      ["before"]
    }

    Newline must not cause a crash:

    iex> input = Unlock.SIRI.parse_incoming("<root>\\n<hello/></root>")
    iex> Unlock.SIRI.RequestorRefReplacer.replace_requestor_ref(input, "ok")
    {
      {"root", [], ["\n", {"hello", [], []}]},
      []
    }
    """

    def replace_requestor_ref(_node, _new_requestor_ref, seen_requestor_refs \\ [])

    def replace_requestor_ref({tag, attributes, [text]} = node, new_requestor_ref, seen_requestor_refs)
        when is_binary(text) do
      [unnamespaced_tag | _] = tag |> String.split(":") |> Enum.reverse()

      if unnamespaced_tag == "RequestorRef" do
        {{tag, attributes, [new_requestor_ref]}, [text | seen_requestor_refs]}
      else
        {node, seen_requestor_refs}
      end
    end

    # required to support non-semantic newline (\n) characters in the XML
    def replace_requestor_ref(node, _, seen_requestor_refs) when is_binary(node) do
      {node, seen_requestor_refs}
    end

    def replace_requestor_ref({tag, attributes, children}, new_requestor_ref, seen_requestor_refs)
        when is_list(children) do
      {children, seen_requestor_refs} =
        Enum.map_reduce(children, seen_requestor_refs, fn e, acc ->
          replace_requestor_ref(e, new_requestor_ref, acc)
        end)

      {{tag, attributes, children}, seen_requestor_refs}
    end
  end
end
