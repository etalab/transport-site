defmodule TransportWeb.DatasetSubtypeLive do
  use TransportWeb, :live_component

  def render(assigns) do
    ~H"""
    <div>
      <div :if={Enum.count(@dataset_subtypes_list) > 0} class="pt-24">
        <.input
          field={@form[:dataset_subtype_input]}
          list="dataset_subtypes"
          phx-keydown="add_subtype"
          phx-target={@myself}
          id="js-dataset-subtype-input"
          label="Sous-type"
        />
        <datalist id="dataset_subtypes" phx-keydown="add_subtype">
          <%= for dataset_subtype <- @dataset_subtypes_list do %>
            <option value={dataset_subtype.slug}>{display(dataset_subtype)}</option>
          <% end %>
        </datalist>
        <div class="pt-6">
          <%= for {dataset_subtype, index} <- @dataset_subtypes |> Enum.sort_by(& &1.slug) |> Enum.with_index() do %>
            <span class="label custom-tag">
              {display(dataset_subtype)}
              <span class="delete-tag" phx-click="remove_subtype" phx-value-slug={dataset_subtype.slug} phx-target={@myself}>
              </span>
            </span>
            <.input field={@form["dataset_subtypes[#{index}]"]} type="hidden" value={dataset_subtype.slug} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def update(assigns, socket) do
    dataset_type = assigns.form[:type].value

    dataset_subtypes_list =
      DB.DatasetSubtype
      |> DB.Repo.all()
      |> Enum.map(&serialize/1)
      |> Enum.filter(&(&1.parent_type == dataset_type))

    dataset_subtypes = assigns.dataset_subtypes |> Enum.map(&serialize/1) |> Enum.filter(&(&1 in dataset_subtypes_list))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:dataset_subtypes, dataset_subtypes)
     |> assign(:dataset_subtypes_list, dataset_subtypes_list)
     |> assign(:dataset_type, dataset_type)}
  end

  def handle_event("add_subtype", %{"key" => "Enter", "value" => value}, socket) do
    new_subtype = Enum.find(socket.assigns.dataset_subtypes_list, &(&1.slug == value))
    dataset_subtypes = (socket.assigns.dataset_subtypes ++ [new_subtype]) |> Enum.uniq()

    if is_nil(new_subtype) do
      {:noreply, socket}
    else
      # new dataset_subtypes list is sent to the parent liveview form
      # because this is a LiveComponent, the process of the parent is the same.
      send(self(), {:updated_dataset_subtypes, dataset_subtypes})
      {:noreply, socket |> clear_input()}
    end
  end

  def handle_event("add_subtype", _, socket) do
    {:noreply, socket}
  end

  def handle_event("remove_subtype", %{"slug" => slug}, socket) do
    dataset_subtypes = Enum.reject(socket.assigns.dataset_subtypes, &(&1.slug == slug))

    send(self(), {:updated_dataset_subtypes, dataset_subtypes})

    {:noreply, socket}
  end

  # clear the input using a js hook
  def clear_input(socket) do
    push_event(socket, "backoffice-form-dataset-subtypes-reset", %{})
  end

  def serialize(%DB.DatasetSubtype{} = subtype) do
    %{
      parent_type: subtype.parent_type,
      slug: subtype.slug
    }
  end

  def serialize(%{parent_type: _, slug: _} = map), do: map

  def display(%{slug: slug}), do: slug
end
