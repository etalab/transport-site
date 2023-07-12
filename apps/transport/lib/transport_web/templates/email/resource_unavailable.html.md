Bonjour,

Les ressources <%= @resource_titles %> dans votre jeu de données <%= link_for_dataset(@dataset, :heex) %> ne sont plus disponibles au téléchargement depuis plus de <%= @hours_consecutive_downtime %>h.

<%= if @deleted_recreated_on_datagouv do %>
Il semble que vous ayez supprimé et créé une nouvelle ressource. Lors de la mise à jour de vos données, privilégiez le remplacement de fichiers. Retrouvez la procédure pas à pas [sur notre documentation](https://doc.transport.data.gouv.fr/producteurs/mettre-a-jour-des-donnees).
<% else %>
Ces erreurs empêchent la réutilisation de vos données.

Nous vous invitons à corriger l'accès de vos données dès que possible.
<% end %>

Nous restons disponible pour vous accompagner si besoin.

Merci par avance pour votre action,

À bientôt,

L'équipe du PAN
