Bonjour,

<%= if Enum.count(@datasets) == 1 do %>
Le saviez-vous ? Il est possible de vous inscrire à des notifications concernant le jeu de données que vous gérez sur transport.data.gouv.fr, <%= @datasets |> hd() |> link_for_dataset() %>.
<% else %>
Le saviez-vous ? Il est possible de vous inscrire à des notifications concernant les jeux de données que vous gérez sur transport.data.gouv.fr :
<ul>
  <%= for dataset <- @datasets do %>
  <li><%= link_for_dataset(dataset) %></li>
  <% end %>
</ul>
<% end %>

Les notifications vous permettent d’être alerté en cas d’expiration, d’indisponibilité et d’erreurs de vos données.

Pour vous inscrire, rien de plus simple : rendez-vous sur votre [Espace Producteur](<%= TransportWeb.Router.Helpers.page_url(TransportWeb.Endpoint, :espace_producteur) %>) dans le menu “Recevoir des notifications”.

Nous restons disponibles pour vous accompagner si besoin.

À bientôt,

L’équipe transport.data.gouv.fr
