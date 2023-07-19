Bonjour,

Les ressources <%= @resource_titles %> dans votre jeu de données <%= link_for_dataset(@dataset, :heex) %> ne sont plus disponibles au téléchargement depuis plus de <%= @hours_consecutive_downtime %>h.

<%= if @deleted_recreated_on_datagouv do %>
Il semble que vous ayez supprimé et créé une nouvelle ressource. Lors de la mise à jour de vos données, remplacez plutôt le fichier au sein de la ressource existante. Retrouvez la procédure pas à pas [sur notre documentation](https://doc.transport.data.gouv.fr/producteurs/mettre-a-jour-des-donnees).

Pour corriger le problème pour cette fois-ci :
1. Mettez à jour l’ancienne ressource avec les nouvelles données en [suivant notre documentation](https://doc.transport.data.gouv.fr/producteurs/mettre-a-jour-des-donnees) ;
2. Supprimez la ressource nouvellement créée qui sera alors en doublon.

<% else %>
Ces erreurs provoquent des difficultés pour les réutilisateurs. Nous vous invitons à corriger l’accès de vos données dès que possible.
<% end %>

Nous restons disponible pour vous accompagner si besoin.

Merci par avance pour votre action,

À bientôt,

L’équipe du PAN
