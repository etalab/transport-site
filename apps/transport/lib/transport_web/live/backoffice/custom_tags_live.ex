defmodule TransportWeb.CustomTagsLive do
  use Phoenix.LiveView
  alias TransportWeb.InputHelpers
  import Ecto.Query

  def render(assigns) do
    ~H"""
    <div class="pt-24">
    <div class="pb-6">

    <%= for {tag, index} <- Enum.with_index(@custom_tags) do %>
      <span class="label custom-tag"><%= tag %> <span class="delete-tag" phx-click="remove_tag" phx-value-tag={tag}></span></span>
    <%= Phoenix.HTML.Form.hidden_input(@form, "custom_tags[#{index}]",
      value: tag
    ) %>
    <% end %>
    </div>
    <%= InputHelpers.text_input(@form, :tag_input,
      placeholder: "Ajouter un tag",
      list: "suggestions",
      phx_keydown: "add_tag",
      id: "custom_tag"
    ) %>
    <datalist id="suggestions" phx-keydown="add_tag",>
      <%= for suggestion <- @tag_suggestions do %>
        <option value={suggestion}><%= suggestion %></option>
      <% end %>
    </datalist>
    </div>
    """
  end

  def mount(
        _params,
        %{"dataset" => %{custom_tags: custom_tags}, "form" => f},
        socket
      )
      when is_list(custom_tags) do
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

  def handle_event("add_tag", %{"key" => "Enter", "value" => tag}, socket) do
    custom_tags = socket.assigns.custom_tags ++ [tag]
    socket = socket |> clear_input() |> assign(:custom_tags, custom_tags)

    {:noreply, socket}
  end

  def handle_event("add_tag", _, socket) do
    {:noreply, socket}
  end

  def handle_event("remove_tag", %{"tag" => tag}, socket) do
    custom_tags = socket.assigns.custom_tags -- [tag]
    {:noreply, assign(socket, :custom_tags, custom_tags)}
  end

  def clear_input(socket) do
    push_event(socket, "backoffice-form-reset", %{})
  end
end
