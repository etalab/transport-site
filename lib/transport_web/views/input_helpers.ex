defmodule TransportWeb.InputHelpers do
  @moduledoc ~S"""
  We override some Phoenix.HTML.Form function to make it easier to integrate template.data.gouv.fr
  """
  alias Phoenix.HTML.Form
  import Phoenix.HTML.Tag

  @doc false
  defmacro __using__(_) do
    quote do
      import Phoenix.HTML
      import Phoenix.HTML.Link
      import Phoenix.HTML.Tag
      import Phoenix.HTML.Format
      import Phoenix.HTML.Form, except: [
        text_input: 3,
        form_for: 3, form_for: 4,
        select: 3, select: 4,
        search_input: 3,
        submit: 1, submit: 2
      ]
    end
  end

  def form_for(form_data, action, options \\ [], fun) when is_function(fun, 1) do
    if Keyword.get(options, :nodiv) do
      Form.form_for(form_data, action, options, fun)
    else
      content_tag(:div,
        Form.form_for(form_data, action, options, fun),
      class: "container"
      )
    end
  end

  def form_group(field) do
    content_tag(:div, field, class: "form__group")
  end

  def select(form, field, options, opts \\ []) do
    form_group(Form.select(form, field, options, opts))
  end

  def search_input(form, field, opts \\ []) do
    button = content_tag(
      :button,
      content_tag(:i, "", class: "fas icon--magnifier"),
       [{:class, "overlay-button"}, {"aria-label", "Recherche"}]
    )
    form_group(
      content_tag(
      :div,
       [Form.text_input(form, field, opts), button],
      class: "search__group"
      )
    )
  end

  def submit([do: _] = block_option), do: submit([], block_option)
  def submit(_, opts \\ [])
  def submit(value, opts) do
    nodiv = Keyword.get(opts, :nodiv)
    opts = opts
    |> Keyword.put_new(:class, "button")
    |> Keyword.drop([:nodiv])

    if nodiv do Form.submit(value, opts) else form_group(Form.submit(value, opts)) end
  end

  def text_input(form, field, opts \\ []) do
    form_group(Form.text_input(form, field, opts))
  end
end
