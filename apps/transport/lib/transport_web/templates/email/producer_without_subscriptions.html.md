Bonjour,

Vous gérez des données présentes sur transport.data.gouv.fr.

## Recevoir des notifications

<%= if Enum.count(@datasets) == 1 do %>
Vous gérez le jeu de données <%= @datasets |> hd() |> link_for_dataset(:heex) %>.
<% else %>
Vous gérez les jeux de données suivants :
<ul>
  <%= for dataset <- @datasets do %>
  <li><%= link_for_dataset(dataset, :heex) %></li>
  <% end %>
</ul>
<% end %>

Pour vous faciliter la gestion de ces données, vous pouvez activer des notifications depuis [votre espace producteur du Point d'accès national](<%= TransportWeb.Router.Helpers.page_url(TransportWeb.Endpoint, :espace_producteur) %>). Elles vous permettront d'être averti de l'[expiration de vos ressources, des erreurs qu'elles peuvent contenir et de leur potentielle indisponibilité](https://doc.transport.data.gouv.fr/producteurs/gerer-la-qualite-des-donnees/sinscrire-aux-notifications#les-differents-types-de-notifications).

## Gestion de vos collègues

<%= if @has_other_contacts do %>
Les autres personnes pouvant s'inscrire à ces notifications et s'étant déjà connecté sont : <%= @contacts_in_orgs %>.
<% end %>

Vous pouvez gérer les membres de vos organisations depuis data.gouv.fr. Si certaines personnes ne font plus partie de votre organisation, vous pouvez supprimer leur accès depuis data.gouv.fr. Si d'autres personnes administrent vos données, elles peuvent [rejoindre votre organisation sur data.gouv.fr](https://doc.transport.data.gouv.fr/producteurs/comment-et-pourquoi-les-producteurs-de-donnees-utilisent-ils-le-pan/creer-une-organisation-sur-data.gouv.fr).

Chacune de ces personnes peut paramétrer des notifications depuis leur espace producteur.

Nous restons disponible pour vous accompagner si besoin.

Bien à vous,
