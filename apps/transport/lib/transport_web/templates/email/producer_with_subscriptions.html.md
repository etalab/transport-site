Bonjour,

Vous gérez des données présentes sur transport.data.gouv.fr.

## Gérer vos notifications

<%= if Enum.count(@datasets_subscribed) == 1 do %>
Vous êtes susceptible de recevoir des notifications pour le jeu de données <%= @datasets_subscribed |> hd() |> link_for_dataset(:heex) %>.
<% else %>
Vous êtes susceptible de recevoir des notifications pour les jeux de données suivants :
<ul>
  <%= for dataset <- @datasets_subscribed do %>
  <li><%= link_for_dataset(dataset, :heex) %></li>
  <% end %>
</ul>
<% end %>

Les notifications facilitent la gestion de vos données. Elles vous permettront d'être averti de l'[expiration de vos ressources, des erreurs qu'elles peuvent contenir et de leur potentielle indisponibilité](https://doc.transport.data.gouv.fr/administration-des-donnees/procedures-de-publication/gerer-la-qualite-des-donnees#sinscrire-aux-notifications#les-differents-types-de-notifications).

Vous pouvez gérer ces notifications depuis [votre espace producteur du Point d'accès national](<%= TransportWeb.Router.Helpers.page_url(TransportWeb.Endpoint, :espace_producteur) %>).

## Gérer les membres de vos organisations

<%= if @has_other_producers_subscribers do %>
Les autres personnes inscrites à ces notifications sont : <%= @other_producers_subscribers %>.
<% end %>

Vous pouvez gérer les membres de vos organisations depuis data.gouv.fr. Si d'autres personnes administrent vos données, elles peuvent [rejoindre votre organisation sur data.gouv.fr](https://doc.transport.data.gouv.fr/administration-des-donnees/procedures-de-publication/creer-un-compte-utilisateur-sur-data.gouv.fr). Chacune de ces personnes peut paramétrer des notifications depuis leur espace producteur.

Nous restons disponible pour vous accompagner si besoin.

Bien à vous,
