Bonjour,

Vous gérez des données présentes sur transport.data.gouv.fr.

## Gérer vos notifications

<%= if Enum.count(@datasets_subscribed) == 1 do %>
Vous êtes susceptible de recevoir des notifications pour le jeu de données <%= @datasets_subscribed |> hd() |> link_for_dataset() %>.
<% else %>
Vous êtes susceptible de recevoir des notifications pour les jeux de données suivants :
<ul>
  <%= for dataset <- @datasets_subscribed do %>
  <li><%= link_for_dataset(dataset) %></li>
  <% end %>
</ul>
<% end %>

Les notifications facilitent la gestion de vos données. Elles vous permettront d’être averti de l’expiration de vos ressources, des erreurs qu’elles peuvent contenir et de leur potentielle indisponibilité.

Vous pouvez gérer ces notifications depuis [votre espace producteur](<%= TransportWeb.Router.Helpers.page_url(TransportWeb.Endpoint, :espace_producteur) %>) du Point d’Accès National.

## Gérer les membres de votre organisation

L’administrateur de votre organisation peut ajouter, modifier ou supprimer les différents membres depuis [votre espace d’administration data.gouv.fr](<%= @manage_organization_url %>).

<%= if @has_other_producers_subscribers do %>
Les autres personnes inscrites à ces notifications sont : <%= @other_producers_subscribers %>.
<% end %>

Chaque utilisateur peut paramétrer ses propres notifications depuis son espace producteur du PAN.

Nous restons disponibles pour vous accompagner si besoin.

À bientôt !
