Bonjour,

Vous gérez des données présentes sur transport.data.gouv.fr.

## Recevoir des notifications

<%= if Enum.count(@datasets) == 1 do %>
Vous gérez le jeu de données <%= @datasets |> hd() |> link_for_dataset() %>.
<% else %>
Vous gérez les jeux de données suivants :
<ul>
  <%= for dataset <- @datasets do %>
  <li><%= link_for_dataset(dataset) %></li>
  <% end %>
</ul>
<% end %>

Pour vous faciliter la gestion de ces données, vous pouvez activer des notifications depuis [votre espace producteur](<%= TransportWeb.Router.Helpers.page_url(TransportWeb.Endpoint, :espace_producteur) %>) du Point d’Accès National. Elles vous permettront d’être averti de l’expiration de vos ressources, des erreurs qu’elles peuvent contenir et de leur potentielle indisponibilité.

## Gérer les membres de votre organisation

L’administrateur de votre organisation peut ajouter, modifier ou supprimer les différents membres depuis [votre espace d’administration data.gouv.fr](<%= @manage_organization_url %>).

<%= if @has_other_contacts do %>
Les autres personnes pouvant s’inscrire à ces notifications et s’étant déjà connectées sont : <%= @contacts_in_orgs %>.
<% end %>

Chaque utilisateur peut paramétrer ses propres notifications depuis son espace producteur du PAN.

Nous restons disponibles pour vous accompagner si besoin.

À bientôt !
