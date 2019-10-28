# Données temps-réel non standardisées

Le Point d'Accès National aux données de transport (PAN) fournit un accès **homogène** à ces données pour en faciliter l’intégration et la réutilisation.

Les exigences pour publication homogène de données temps-réel de lignes régulières (bus etc.) sont détaillées [sur cette page](https://doc.transport.data.gouv.fr/producteurs/operateurs-de-transport-regulier-de-personnes/temps-reel-des-transports-en-commun). 

Cependant, certains réseaux de transport disposent de données temps-réel non standardisées. Celles-ci n'ont pas vocation à être référencées sur le PAN en l'état, mais elles sont listées ci-dessous pour référence.


<table class="table">
<th>Nom</th>
<th>Format</th>
<th>Bulk</th>
<th>Accès ouvert</th>
<th>Licence</th>
<th>Prochains passages</th>
<th>Position véhicules</th>
<th>Messages d’alerte</th>
<%= for p <- @providers do %>
<tr>
<td><%= p["aom"] %></td>
<td><%= p["format"] %></td>
<td><%= thumb(p["bulk"]) %></td>
<td><%= thumb(p["acces_ouvert"]) %>
<td><%= p["licence"] %></td>
<td><%= make_link(p["prochains_passages"]) %></td>
<td><%= make_link(p["position_vehicules"]) %></td>
<td><%= make_link(p["alertes"]) %></td>
</tr>
<% end %>
</table>
  
Vous pouvez signaler à l'équipe du PAN un jeu de données à ajouter ci-dessus en écrivant à contact@transport.beta.gouv.fr.
