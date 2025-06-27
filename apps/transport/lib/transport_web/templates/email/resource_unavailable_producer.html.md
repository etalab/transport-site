Bonjour,

Les ressources <%= @resource_titles %> dans votre jeu de données <%= link_for_dataset(@dataset) %> ne sont plus disponibles au téléchargement depuis plus de <%= @hours_consecutive_downtime %>h.

<%= if @deleted_recreated_on_datagouv do %>
Il semble que vous ayez supprimé puis créé une nouvelle ressource : l’URL de téléchargement a donc été modifiée ce qui risque de perturber la réutilisation de vos données. Si ce constat est avéré, nous vous encourageons à prévenir les réutilisateurs de la modification de l’URL de téléchargement via <%= link_for_dataset_discussions(@dataset) %>.

Pour les prochaines mises à jour, afin de garantir une URL stable, nous vous invitons à remplacer votre ressource obsolète par la nouvelle.

Pour cela, rendez-vous sur votre <%= link_for_espace_producteur(:resource_unavailable_producer) %> à partir duquel vous pourrez procéder à ces mises à jour.

Retrouvez la procédure pas à pas [sur notre documentation](https://doc.transport.data.gouv.fr/producteurs/mettre-a-jour-des-donnees).
<% else %>
Nous vous invitons à corriger l’accès à vos données dès que possible afin de ne pas perturber leur réutilisation.
<% end %>

Nous restons disponibles pour vous accompagner si besoin.

À bientôt,

L’équipe transport.data.gouv.fr

*Ce mail est envoyé automatiquement. Vous pouvez contacter l'équipe de transport.data.gouv.fr en réponse de ce mail pour toute information complémentaire.*
