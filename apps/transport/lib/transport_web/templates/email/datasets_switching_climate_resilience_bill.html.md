Bonjour,

<%= unless Enum.empty?(@datasets_now_climate_resilience) do %>
<!--
Article 122 loi climat et résilience, will be back
https://github.com/etalab/transport-site/issues/3149
Update text
-->
Les jeux de données suivants feront l’objet d’une intégration obligatoire :
<%= for dataset <- @datasets_now_climate_resilience do %>
<%= link_for_dataset(dataset) %>
<% end %>
<% end %>

<%= unless Enum.empty?(@datasets_previously_climate_resilience) do %>
Les jeux de données suivants faisaient l’objet d’une intégration obligatoire et ne font plus l’objet de cette obligation :
<%= for dataset <- @datasets_previously_climate_resilience do %>
<%= link_for_dataset(dataset) %>
<% end %>
<% end %>

L’équipe transport.data.gouv.fr
