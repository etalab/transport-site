# adapted from https://github.com/qcam/saxy/blob/master/lib/saxy/simple_form/handler.ex
defmodule SIRI.Saxy.Handler do
  @moduledoc """
  This is a Saxy-compliant handler to parse (& slightly modify) XML.

  It is just a thin wrapper on top of https://github.com/qcam/saxy/blob/master/lib/saxy/simple_form/handler.ex.

  Provides functions to parse a XML document to [simple-form](http://erlang.org/doc/man/xmerl.html#export_simple-3) data structure,
  and modify the requestor ref on the fly.
  """

  @behaviour Saxy.Handler

  @impl Saxy.Handler
  def handle_event(:start_document, prolog, state) do
    {:ok, parsed_doc} = Saxy.SimpleForm.Handler.handle_event(:start_document, prolog, state.parsed_doc)
    {:ok, %{state | parsed_doc: parsed_doc}}
  end

  @impl Saxy.Handler
  def handle_event(:start_element, data, state) do
    {:ok, parsed_doc} = Saxy.SimpleForm.Handler.handle_event(:start_element, data, state.parsed_doc)
    {:ok, %{state | parsed_doc: parsed_doc}}
  end

  @impl Saxy.Handler
  def handle_event(:characters, chars, state) do
    stack = state.parsed_doc
    [{tag_name, attributes, content} | stack] = stack

    # TODO: record the SIRI namespace instead
    unnamespaced_tag = tag_name |> String.split(":") |> List.last()

    {chars, state} = if unnamespaced_tag == "RequestorRef" do
        {state.new_requestor_ref, Map.put(state, :incoming_requestor_ref, chars)}
      else
        {chars, state}
      end

    current = {tag_name, attributes, [chars | content]}

    {:ok, %{state | parsed_doc: [current | stack]}}
  end

  # untested
  @impl Saxy.Handler
  def handle_event(:cdata, chars, state) do
    {:ok, parsed_doc} = Saxy.SimpleForm.Handler.handle_event(:cdata, chars, state.parsed_doc)
    {:ok, %{state | parsed_doc: parsed_doc}}
  end

  @impl Saxy.Handler
  def handle_event(:end_element, tag_name, state) do
    {:ok, parsed_doc} = Saxy.SimpleForm.Handler.handle_event(:end_element, tag_name, state.parsed_doc)
    {:ok, %{state | parsed_doc: parsed_doc}}
  end

  @impl Saxy.Handler
  def handle_event(:end_document, some_param, state) do
    {:ok, parsed_doc} = Saxy.SimpleForm.Handler.handle_event(:end_document, some_param, state.parsed_doc)
    {:ok, %{state | parsed_doc: parsed_doc}}
  end
end
