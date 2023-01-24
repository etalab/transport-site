defmodule TransportWeb.CustomTagsLive do
  use Phoenix.LiveView
  alias TransportWeb.InputHelpers
  import Ecto.Query

  def render(assigns) do
    ~H"""
    <%= for tag <- @custom_tags do %>
      <span class="label"><%= tag %></span>
    <% end %>
    <%= InputHelpers.text_input(@form, :custom_tags,
      placeholder: "tag",
      value: "",
      list: "suggestions",
      id: "custom_tag"
    ) %>
    <datalist id="suggestions">
      <%= for suggestion <- @tag_suggestions do %>
        <option value={suggestion}><%= suggestion %></option>
      <% end %>
    </datalist>
    """
  end

  def mount(
        _params,
        %{"dataset" => %{custom_tags: custom_tags}, "form" => f},
        socket
      ) do
    {:ok, mount_assigns(socket, custom_tags, f)}
  end

  def mount(
        _params,
        %{"form" => f},
        socket
      ) do
    {:ok, mount_assigns(socket, [], f)}
  end

  def mount_assigns(socket, custom_tags, form) do
    tag_suggestions =
      DB.Dataset.base_query()
      |> select([d], fragment("unnest(custom_tags)"))
      |> DB.Repo.all()

    socket
    |> assign(:custom_tags, custom_tags)
    |> assign(:form, form)
    |> assign(:tag_suggestions, tag_suggestions)
  end

  # def handle_event("tag_change", %{"value" => tag}, socket) do
  #   {:noreply, socket}
  # end
end
