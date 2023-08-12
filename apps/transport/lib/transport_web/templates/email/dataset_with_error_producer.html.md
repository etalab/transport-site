Bonjour,

Des erreurs bloquantes ont été détectées dans votre jeu de données <%= link_for_dataset(@dataset) %>. Ces erreurs empêchent la réutilisation de vos données.

Nous vous invitons à les corriger en vous appuyant sur les rapports de validation suivants :
<%= for resource <- @resources do %>
<%= link_for_resource(resource) %>
<% end %>

Nous restons disponible pour vous accompagner si besoin.

Merci par avance pour votre action,

À bientôt,

L'équipe du PAN
