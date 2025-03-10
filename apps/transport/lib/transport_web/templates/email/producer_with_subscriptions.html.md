Bonjour,

<%= if Enum.count(@datasets_subscribed) == 1 do %>
En tant que producteur de données de transport, vous êtes inscrit à des notifications pour le jeu de données <%= @datasets_subscribed |> hd() |> link_for_dataset() %>.
<% else %>
En tant que producteur de données de transport, vous êtes inscrit à des notifications concernant les jeux de données suivants :
<ul>
  <%= for dataset <- @datasets_subscribed do %>
  <li><%= link_for_dataset(dataset) %></li>
  <% end %>
</ul>
<% end %>

Les notifications vous permettent d’être alerté en cas d’expiration, d’indisponibilité et d’erreurs de vos données. Si vous souhaitez gérer vos notifications, rendez-vous sur votre <%= link_for_espace_producteur(:periodic_reminder_producer_with_subscriptions) %>.

<%= if @has_other_producers_subscribers do %>
Les autres personnes impliquées dans la production ou publication de vos données (qu’ils soient exploitants, intervenants techniques ou responsables légaux) et inscrites à ces notifications sont : <%= @other_producers_subscribers %>.
<% end %>

Nous restons disponibles pour vous accompagner si besoin.

À bientôt,

L’équipe transport.data.gouv.fr
