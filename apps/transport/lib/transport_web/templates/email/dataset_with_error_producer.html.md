Bonjour,

Des erreurs bloquantes ont été détectées dans votre jeu de données <%= link_for_dataset(@dataset) %>. Ces erreurs empêchent la réutilisation de vos données.

Nous vous invitons à les corriger en vous appuyant sur les rapports de validation suivants :
<%= for resource <- @resources do %>
<%= link_for_resource(resource) %>
<% end %>

Nous restons disponibles pour vous accompagner si besoin.

Merci par avance pour votre action,

À bientôt,

L’équipe transport.data.gouv.fr

*Ce mail est envoyé automatiquement. Vous pouvez contacter l'équipe de transport.data.gouv.fr en réponse de ce mail pour toute information complémentaire.*
