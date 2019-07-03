# Données temps réel

L’objectif du point d’accès national des données transport est de fournir un accès homogène aux données pour faciliter l’intégration.

Une explication détaillée des variantes est disponible [sur notre page d’aide](https://doc.transport.data.gouv.fr/producteurs/temps-reel-des-transports-en-commun).

Le point d’accès `Siri Lite` et `GTFS-RT` pour tous les jeux de données est (tr.transport.data.gouv.fr)[https://tr.transport.data.gouv.fr].

Les [jeux de données disponibles](<%= dataset_url(@conn, :index, filter: :has_realtime) %>) sur transport.data.gouv.fr respectent ainsi toutes les conditions suivantes :

* Horaires théoriques disponibles,
* Horaires en temps réel (avance/retard des véhicules),
* Au format GTFS-RT (au moins _trip updates_),
* API Siri-lite (au moins _stop monitoring_ et _stop discovery_),
* Données utilisables au moins selon les conditions de la licence _ODbL_,
* Pas d’authentification,
* Pas de restriction de requêtage (nous nous réservons de couper les accès dépassant 1 requête par seconde).

## Autres sources de temps réel

D’autres réseaux disposent de données temps. Même si elles ne répondent pas à tous les critères du point d’accès national, elles peuvent intéresser certains ré-utilisateurs. Nous les référençons ici :


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
