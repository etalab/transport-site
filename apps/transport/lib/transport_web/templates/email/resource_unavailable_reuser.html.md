Bonjour,

Les ressources <%= @resource_titles %> du jeu de données <%= link_for_dataset(@dataset) %> que vous réutilisez ne sont plus disponibles au téléchargement depuis plus de <%= @hours_consecutive_downtime %>h.

<%= if @producer_warned do %>
Le producteur de ces données a été informé de cette indisponibilité.
<% end %>

L’équipe du PAN
