Bonjour,

Les ressources <%= @resource_titles %> du jeu de données <%= link_for_dataset(@dataset) %> que vous réutilisez ne sont plus disponibles au téléchargement depuis plus de <%= @hours_consecutive_downtime %>h.

<%= if @producer_warned do %>
Nous avons déjà informé le producteur de ces données. Si l’indisponibilité perdure, vous pouvez contacter le producteur à partir de <%= link_for_dataset_discussions(@dataset) %>.
<% end %>

À bientôt,

L’équipe transport.data.gouv.fr
