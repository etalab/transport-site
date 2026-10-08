defmodule TransportWeb.CoreComponentsTest do
  use ExUnit.Case, async: true
  require Phoenix.LiveViewTest

  @params %{"name" => "Bob", "kind" => "b", "accept" => "true", "q" => "bus", "comment" => "hi <3"}

  test "text input" do
    assert_html(input(field: form()[:name]), ~s(<div class="form__group">
      <input id="user_name" name="user[name]" type="text" value="Bob"></div>))

    assert_html(
      input(field: form()[:name], label: "Nom", placeholder: "ex", required: true),
      ~s(<div class="form__group"><label class="required" for="user_name">Nom</label>
      <input id="user_name" name="user[name]" placeholder="ex" required type="text" value="Bob"></div>)
    )

    assert_html(input(field: form()[:name], type: "number"), ~s(<div class="form__group">
      <input id="user_name" name="user[name]" type="number" value="Bob"></div>))
  end

  test "email input" do
    assert_html(input(field: form()[:name], type: "email", required: true), ~s(<div class="form__group">
      <input id="user_name" name="user[name]" required type="email" value="Bob"></div>))
  end

  test "search input" do
    assert_html(
      input(field: form()[:q], type: "search", id: "s", placeholder: "Chercher", autocomplete: "off"),
      ~s(<div class="form__group"><div class=""><i class="fas icon--magnifier" id="magnifier"></i>
      <input autocomplete="off" id="s" name="user[q]" placeholder="Chercher" type="search" value="bus"></div></div>)
    )
  end

  test "select" do
    assert_html(
      input(field: form()[:kind], type: "select", label: "Type", options: [{"A", "a"}, {"B", "b"}]),
      ~s(<div class="form__group"><label for="user_kind">Type</label><select id="user_kind" name="user[kind]">
      <option value="a">A</option><option selected value="b">B</option></select></div>)
    )
  end

  test "textarea" do
    assert_html(input(field: form()[:comment], type: "textarea", required: true), ~s(<div class="form__group">
      <textarea id="user_comment" name="user[comment]" required>\nhi &lt;3</textarea></div>))

    assert_html(
      input(field: form()[:comment], type: "textarea", autoexpand: true),
      ~s(<div class="form__group"><div class="autoexpand">
      <textarea id="user_comment" name="user[comment]" phx-hook="TextareaAutoexpand">\nhi &lt;3</textarea></div></div>)
    )
  end

  test "file input" do
    assert_html(
      input(field: form()[:name], type: "file", label: "Fichier", accept: ".zip"),
      ~s(<div class="form__group">
      <label for="user_name">Fichier</label><input accept=".zip" id="user_name" name="user[name]" type="file"></div>)
    )
  end

  test "checkbox" do
    assert_html(
      input(field: form()[:accept], type: "checkbox", label: "J'accepte"),
      ~s(<div class="form__group"><input name="user[accept]" type="hidden" value="false">
      <input checked id="user_accept" name="user[accept]" type="checkbox" value="true">
      <label class="label-inline" for="user_accept">J'accepte</label></div>)
    )
  end

  test "hidden input" do
    assert_html(input(field: form()[:name], type: "hidden", value: "v"), ~s(
      <input id="user_name" name="user[name]" type="hidden" value="v">))
  end

  test "without wrapper" do
    assert_html(input(field: form()[:name], wrapper: false), ~s(
      <input id="user_name" name="user[name]" type="text" value="Bob">))

    assert_html(
      input(field: form()[:kind], type: "select", options: [{"A", "a"}, {"B", "b"}], wrapper: false),
      ~s(<select id="user_kind" name="user[kind]"><option value="a">A</option><option selected value="b">B</option></select>)
    )

    assert_html(input(field: form()[:accept], type: "checkbox", wrapper: false), ~s(
      <input name="user[accept]" type="hidden" value="false">
      <input checked id="user_accept" name="user[accept]" type="checkbox" value="true">))
  end

  test "help" do
    assert_html(
      input(field: form()[:name], label: "Nom", help: [%{inner_block: fn _, _ -> "Optionnel" end}]),
      ~s(<div class="form__group"><label for="user_name">Nom</label>
      <input id="user_name" name="user[name]" type="text" value="Bob"><div class="small">Optionnel</div></div>)
    )
  end

  test "errors are shown once the field is used" do
    form = Phoenix.Component.to_form(@params, as: :user, errors: [name: {"a custom error", []}])

    assert_html(input(field: form[:name]), ~s(<div class="form__group">
      <input id="user_name" name="user[name]" type="text" value="Bob">
      <span class="help-block">a custom error</span></div>))
  end

  test "button" do
    assert_html(button([]), ~s(<button class="button" type="submit">Envoyer</button>))
    assert_html(button(class: "button-outline"), ~s(<button class="button-outline" type="submit">Envoyer</button>))
    assert_html(button(href: "/datasets"), ~s(<a class="button" href="/datasets">Envoyer</a>))
  end

  defp form, do: Phoenix.Component.to_form(@params, as: :user)

  defp input(assigns), do: Phoenix.LiveViewTest.render_component(&TransportWeb.CoreComponents.input/1, assigns)

  defp button(assigns) do
    assigns = Keyword.put(assigns, :inner_block, [%{inner_block: fn _, _ -> "Envoyer" end}])
    Phoenix.LiveViewTest.render_component(&TransportWeb.CoreComponents.button/1, assigns)
  end

  defp assert_html(rendered, expected), do: assert(normalize(rendered) == normalize(expected))

  defp normalize(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.traverse_and_update(fn
      {tag, attrs, children} -> {tag, Enum.sort(attrs), Enum.reject(children, &blank?/1)}
      other -> other
    end)
    |> Enum.reject(&blank?/1)
  end

  defp blank?(node), do: is_binary(node) and String.trim(node) == ""
end
