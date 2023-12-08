Bonjour,

<%= if Enum.count(@datasets_subscribed) == 1 do %>
Vous êtes inscrit à des notifications pour le jeu de données <%= @datasets_subscribed |> hd() |> link_for_dataset() %>.
<% else %>
Vous êtes inscrit à des notifications concernant les jeux de données suivants :
<ul>
  <%= for dataset <- @datasets_subscribed do %>
  <li><%= link_for_dataset(dataset) %></li>
  <% end %>
</ul>
<% end %>

Les notifications vous permettent d’être alerté en cas d’expiration, d’indisponibilité et d’erreurs de vos données. Rendez-vous sur votre [Espace Producteur](<%= TransportWeb.Router.Helpers.page_url(TransportWeb.Endpoint, :espace_producteur) %>) pour les gérer de manière autonome.

<%= if @has_other_producers_subscribers do %>
Les autres personnes inscrites à ces notifications sont : <%= @other_producers_subscribers %>.
<% end %>

Nous restons disponibles pour vous accompagner si besoin.

À bientôt,

L’équipe transport.data.gouv.fr
