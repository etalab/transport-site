# Qui sont les réutilisateurs de vos données ?

Les réutilisateurs suivants déploient leurs services de mobilité sur les territoires des acteurs du transport ayant ouvert leurs données. Ainsi, de plus en plus d’usagers peuvent en profiter et bénéficier d’une information voyageur plus complète lors de leurs déplacements.

<table>
  <tr>
    <th>Réutilisateur</th>
    <th>Description</th>
    <th>Couverture</th>
  </tr>
  <tr>
    <td>MyBus</td>
    <td>MyBus exploite un modèle applicatif générique pouvant s’adapter à tous les réseaux de transport en commun. MyBus propose aussi une solution de M-Ticketing, gratuite, universelle et prête à l’emploi.</td>
    <td>100 réseaux urbains</td>
  </tr>
  <tr>
    <td>Mappy</td>
    <td>Mappy est un comparateur d'itinéraires pour préparer vos déplacements en France et en Europe sur Internet et Mobile.</td>
    <td>44 réseaux urbains</td>
  </tr>
  <tr>
    <td>Handisco</td>
    <td>Handisco a développé le 1er assistant intelligent qui décuple les possibilités d'une canne blanche et facilite les déplacements des déficients visuels</td>
    <td>58 réseaux urbains</td>
  </tr>
  <tr>
    <td>Transit</td>
    <td>Transit vous affiche toutes les options de transport disponibles autour de vous ainsi que les prochains horaires de départ – accès instantané à l'information dont vous avez le plus besoin. </td>
    <td>24 réseaux urbains</td>
  </tr>
  <tr>
    <td>Here Technologies</td>
    <td>Here Technologies offre les meilleures cartes du monde et expériences de localisation sur tous les supports possibles (appareils connectés fixes et mobiles) et pour toutes les applications possibles.</td>
    <td>Information non communiquée</td>
  </tr>
  <tr>
    <td>Kisio Digital</td>
    <td>Kisio Digital transforme la mobilité des villes et des territoires par le service. </td>
    <td>Information non communiquée</td>
  </tr>
  <tr>
    <td>Urban Pulse</td>
    <td>Urban Pulse est la première application smartphone intégrant l'ensemble des informations et des services utiles pour connaître en temps réel tout ce qui se passe autour de vous. Et elle vous y emmène facilement par les moyens de transport les plus rapides.</td>
    <td>Information non communiquée</td>
  </tr>
  <tr>
    <td>MobiGIS</td>
    <td>MobiGIS se positionne comme éditeur de logiciels et société de services spécialisée dans les Systèmes d’Information Géographique (SIG) intervenant dans les domaines du transport et de la mobilité des personnes.</td>
    <td>Information non communiquée</td>
  </tr>
<%= for partner <- @conn.assigns.partners do %>
  <tr>
    <td><%= partner.name %></td>
    <td><%= partner.description %></td>
    <td><%= partner.count_reuses %> réseaux urbains</td>
  </tr>
<% end %>
</table>


## Autres partenaires

Les partenaires suivants ont contribué à l’ouverture des données transport.

<table>
  <tr>
    <th>Partenaire</th>
    <th>Description</th>
    <th>Contribution</th>
  </tr>
  <tr>
    <td>Blablacar</td>
    <td>BlaBlaCar, premier réseau de covoiturage, met en relation des voyageurs pour leur permettre d'aller partout. Plus besoin d'aller en ville pour quitter la ville.</td>
    <td>Consolidation d’un fichier national des aires de covoiturage</td>
  </tr>
  <tr>
    <td>La Fabrique des Mobilités</td>
    <td>La Fabrique des Mobilités est le premier accélérateur européen dédié à un écosystème en mutation : celui des acteurs du transport et des mobilités.</td>
    <td>Consolidation d’un fichier crowdsourcé des lieux de covoiturage</td>
  </tr>
</table>

Vous êtes un réutilisateur de données référencées sur ce site et vous souhaitez apparaître sur cette page ?
Contactez-nous à <a href="mailto:contact@transport.beta.gouv.fr">contact@transport.beta.gouv.fr</a>.
