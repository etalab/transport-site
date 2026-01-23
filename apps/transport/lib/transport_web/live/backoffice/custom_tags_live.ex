defmodule TransportWeb.CustomTagsLive do
  use Phoenix.LiveComponent
  alias TransportWeb.InputHelpers
  import Ecto.Query

  def render(assigns) do
    ~H"""
    <div class="pt-24">
      {InputHelpers.text_input(@form, :tag_input,
        placeholder: "Ajouter un tag",
        list: "suggestions",
        phx_keydown: "add_tag",
        phx_change: "change",
        id: "custom_tag",
        phx_target: @myself,
        label: "Tags"
      )}
      <div class="pt-6">
        <%= for {tag, index} <- Enum.with_index(@custom_tags) do %>
          <span class="label custom-tag">
            {tag} <span class="delete-tag" phx-click="remove_tag" phx-value-tag={tag} phx-target={@myself}></span>
          </span>
          {Phoenix.HTML.Form.hidden_input(@form, "custom_tags[#{index}]", value: tag)}
        <% end %>
      </div>
      <datalist id="suggestions">
        <%= for suggestion <- @tag_suggestions do %>
          <option value={suggestion}>{suggestion}</option>
        <% end %>
      </datalist>
      <details class="pt-12">
        <summary>Tags liés à des fonctionnalités</summary>
        <ul>
          <%= for tag_doc <- Enum.sort_by(@tags_documentation, & &1.name) do %>
            <li><span class="label"><%= tag_doc.name %></span>{tag_doc.doc}</li>
          <% end %>
        </ul>
      </details>
    </div>
    """
  end

  def tags_suggestions do
    tags_in_database =
      DB.Dataset.base_with_hidden_datasets()
      |> select([dataset: d], fragment("distinct unnest(custom_tags)"))
      |> DB.Repo.all()

    documented_tags = Enum.map(tags_documentation(), & &1.name)

    (tags_in_database ++ documented_tags) |> Enum.sort() |> Enum.dedup()
  end

  def tags_documentation do
    [
      %{name: "licence-mobilités", doc: "Applique la licence mobilités pour ce jeu de données"},
      %{
        name: "loi-climat-resilience",
        doc:
          "Ce jeu de données est soumis à l'obligation de réutilisation selon l'article 122 de la loi climat et résilience"
      },
      %{name: "requestor_ref:<valeur>", doc: "Renseigne le requestor_ref des ressources SIRI pour ce jeu de données"},
      %{name: "saisonnier", doc: "Indique sur la page du JDD que ce jeu de données n'opère qu'une partie de l'année"},
      %{name: "skip_history", doc: "Désactive l'historisation des ressources pour ce jeu de données"},
      %{
        name: "masqué",
        doc:
          "Masque ce jeu de données des statistiques, de la recherche et de l'API. Le jeu reste accessible via son URL directe (web et API)."
      },
      %{
        name: "authentification_requise",
        doc: "Indique sur la page du JDD qu'il est nécessaire de s'authentifier pour accéder aux données."
      },
      %{
        name: "experimental",
        doc: "Ajoute sur la page du JDD une bannière indiquant que le jeu est expérimental"
      },
      %{
        name: Application.fetch_env!(:transport, :data_sharing_pilot_dataset_custom_tag),
        doc: "Indique que ce jeu de données est éligible à l'expérimentation du repartage de données améliorées"
      },
      %{
        name: "authentification_experimentation",
        doc: "Indique que pour ce jeu de données on utilisera des URLs en transport.data.gouv.fr"
      }
    ]
  end

  def mount(socket) do
    {:ok,
     socket
     |> assign(
       tags_documentation: tags_documentation(),
       tag_suggestions: tags_suggestions()
     )}
  end

  def handle_event("change", %{"form" => %{"tag_input" => tag}}, socket) do
    if tag in socket.assigns.tag_suggestions do
      add_tag(tag, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_tag", %{"key" => "Enter", "value" => tag}, socket) do
    add_tag(tag, socket)
  end

  def handle_event("add_tag", _, socket) do
    {:noreply, socket}
  end

  def handle_event("remove_tag", %{"tag" => tag}, socket) do
    custom_tags = socket.assigns.custom_tags -- [tag]
    send(self(), {:updated_custom_tags, custom_tags})

    {:noreply, socket}
  end

  defp add_tag(tag, socket) do
    # Do not lowercase a tag for a SIRI requestor_ref
    clean_tag =
      if String.starts_with?(tag, "requestor_ref:") do
        tag |> String.trim()
      else
        tag |> String.downcase() |> String.trim()
      end

    custom_tags = (socket.assigns.custom_tags ++ [clean_tag]) |> Enum.uniq()
    send(self(), {:updated_custom_tags, custom_tags})

    {:noreply, socket |> clear_input()}
  end

  def clear_input(socket) do
    push_event(socket, "backoffice-form-reset", %{})
  end
end
