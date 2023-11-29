Bonjour,

Des erreurs bloquantes ont été détectées dans le jeu de données <%= link_for_dataset(@dataset) %> que vous réutilisez.

<%= if @producer_warned do %>
Nous avons déjà informé le producteur de ces données. Si les erreurs ne sont pas corrigées, vous pouvez contacter le producteur à partir de <%= link_for_dataset_discussions(@dataset) %>.
<% end %>

L’équipe transport.data.gouv.fr
