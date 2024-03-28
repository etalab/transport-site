Bonjour,

Des discussions ont eu lieu sur certains jeux de données que vous suivez. Vous pouvez prendre connaissance de ces échanges.

<%= for dataset <- @datasets do %>
- <%= link_for_dataset_section(dataset, :discussion) %>
<% end %>

L’équipe transport.data.gouv.fr
