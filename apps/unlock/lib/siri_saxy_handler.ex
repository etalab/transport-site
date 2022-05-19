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
  def handle_event(:start_document, prolog, %{new_requestor_ref: _} = state) do
    state = Map.put(state, :parsed_doc, [])

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

    # NOTE: proper namespace handling not added for now
    unnamespaced_tag = tag_name |> XMLHelper.unnamespace()

    {chars, state} =
      if unnamespaced_tag == "RequestorRef" do
        # NOTE: an array should be used instead of erasing the key, because it would
        # otherwise allow duplicate elements with a risk to erase the previous ref
        # Important note: here we replace the existing requestor ref, all while
        # saving the previous one for verification.
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
