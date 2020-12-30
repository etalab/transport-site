---
title: "La production des données temps réel pour les transports en commun "
date: 2020-12-23T09:33:17.115Z
tags:
  - retour d'expérience
description: >
  Interview avec différents producteurs de données temps réel et services de
  traitement de ces données afin de mieux comprendre les enjeux autour de la
  production des données temps réel. 



  Nous nous sommes également entretenus avec des collectivités ayant publié leurs données sur le Point d'Accès National (PAN) afin de mieux comprendre la relation avec les producteurs et services de normalisation des données.
---
**Personnes interviewées :**

Producteurs de données 

* [Zenbus](https://www.data.gouv.fr/fr/organizations/zenbus/), Olivier Deschasseaux co-fondateur en charge des partenariats, du marketing et de la communication

Services de géolocalisation temps réel à partir de smartphones et production de données temps réel dans des formations normalisés (GTFS-RT et SIRI)

* Kisio Digital : Betrand Billoud et Laetitia Paternoster

Service accompagnant tous les acteurs de la mobilité pour créer,\
déployer et animer les services à la mobilité.

*  Pysae : Maxime Cabanel Responsable grands comptes 

Solution pour système d'aide à l'exploitation et à l'information voyageurs (SAEIV) clé en main pour les conducteurs de bus, les exploitants et les voyageurs. 

* [City Way](https://www.data.gouv.fr/fr/organizations/cityway/), Nely Escoffier

Entreprise spécialisée dans le traitement des systèmes d’informations multimodaux (SIM) et la mise en œuvre de solutions numériques depuis une vingtaine d’année

* [Mecatran](https://www.data.gouv.fr/fr/organizations/mecatran/), Laurent Grégoire directeur technique et Nicolas Taillade directeur de la société

éditeur de logiciel travaillant avec les transporteurs publiques pour l'amélioration, la normalisation et l'intégration de données statiques, temps réel et conjecturelles \
Ubitransport 



Collectivités 

* Grand Poitiers, Nicolas Madignier gestionnaire de la data Mobilité Transport et du développement numérique à la Direction Mobilités
* Communauté de l’agglomération de l'Auxerrois, François Meyer chef du service mobilité

<!--StartFragment-->

[transport.data.gouv.fr ](transport.data.gouv.fr)est le point d'accès national (PAN) aux données mobilité. Il a pour mission de rassembler l'ensemble des données servant à l'information voyageur dans des formats harmonisés et sans obligation d'authentification pour les réutilisateurs. Cette ouverture des données vise à faciliter les déplacements des citoyens par l'intégration de ces données dans des services tiers comme des calculateurs d'itinéraires, des cannes connectées, des bureaux d'aménagement du territoire etc. On retrouve cette diversité de service servant à l'information voyageur dans les réutilisateurs du PAN.

![](/images/capturmmme.png)

 *\    Réutilisateurs 30.12.2020*

Il existe trois niveaux de fraîcheur pour les données relatives aux transports : 

* les horaires théoriques : horaires prévisionnels diffusés sous forme d'heure ou de fréquence de passage. 
* les horaires adaptés : les horaires théoriques peuvent être modifiés lorsqu'il y a des évènements modifiant les horaires et/ou itinéraires des véhicules. Par exemple, la RATP diffuse un plan de transport mise à jour en cas de grève, la SNCF livre un patch lorsqu'il y a des changements majeurs sur les horaires théoriques initialement transmis. Ces horaires ne peuvent toutefois pas être considérés comme étant en temps-réel. 
* les horaires temps réel : les horaires affichés correspondent à l'état du trafic à l'instant. 

Cet article traitera exclusivement des données temps-réel pour les transports en commun. 



## Les données temps réel : de la production à la diffusion 

Les données temps réel permettent de fournir une information voyageur qui reflète la réalité du terrain. Ces données peuvent servir à la fois à la gestion de l’exploitation et à l’information des voyageurs. Cette information voyageur permet aux usagers d'optimiser leur temps de trajet. Seules les informations servant à l'informations voyageur sont publiques. Elles permettent à un usager d'être notifié si son bus a du retard par exemple, si il y a des déviations à certains arrêts pour des travaux etc. Pour ce faire, il existe trois formats harmonisés et supportés par le PAN afin de modéliser cette information : 

* **Le GTFS-RT (General Transit Feed Specification - realtime)**

C'est un standard conçu par Google mais qui est désormais maintenu par une communauté open data. 

C'est un un format binaire compact (protobuf) qui utilise une méthode globale permettant de récupérer toutes les données d'un réseau en une requête. 

 Ce flux temps réel peut contenir trois types d'information : 

* `TripUpdate` qui correspond à la mise à jour des horaires de passage
* `Alert`  qui génère des alertes de service
* `VehiclePositions` qui renseigne la position des véhicules

Certains flux proposent toutes ces informations dans un seul flux, comme [Zenbus](https://transport.data.gouv.fr/datasets?_utf8=%E2%9C%93&q=zenbus), mais certains producteurs préfèrent avoir un flux par type de données. C'est le cas pour la [Communauté de l’Auxerrois](https://transport.data.gouv.fr/datasets/reseau-de-transports-en-commun-de-la-communaute-dagglomeration-de-lauxerrois/) qui a publié un flux pour `TripUpdate`et un autre pour `VehiclePositions`

![](/images/capturemls.png)

Il doit être accompagné d'un fichier théorique au format GTFS pour pouvoir être utilisé. Ces données ne sont pas donc pas autoporteuses.\
Par exemple, pour les données de mise à jour des horaires (`TripUpdate`), pour un `Trip` donné on a la mise à jour de ses horaires pour la journée, mais pas d'informations concernant la `Route` de ce `Trip` ni la position des arrêts. Ces informations sont fournis dans le GTFS. 

* **Le SIRI (Service Interface for Realtime Information)**

Le SIRI est une norme définie par le Comité Européen de Normalisation et correspond à la norme [Netex](http://netex-cen.eu/) pour le temps réel. Elle caractérise des services temps réel dont les principaux sont : 

* `Stop Monitoring` qui affiche les prochains passages
* `Estimated Timetable` qui met à jour des horaires de passage)
* `General Message` qui génère des alertes de service
* `Vehicle Monitoring` qui renseigne la position des véhicules

Tout comme le Netex, un profil doit être défini. C'est un format autoporteur mais les données ne sont pas interopérables entre les profils car les services définis sont sélectionnées avec les profils.

* **Le SIRI Lite**

Le SIRI Lite est un sous dérivé de SIRI qui ne contient que les informations suivantes afin de le rendre plus accessible : 

* `StopMonitoring` qui affiche les prochains passages
* `StopPointsDiscovery` / `LineDiscovery` qui fournit des informations sur le réseau
* `GeneralMessage`  qui génère des alertes de service

Le flux est en `JSON` (au lieu de `XML`) et est accessible par une API http classique.

**Les clients des producteurs de données temps réel** 

Les producteurs de données temps-réel peuvent avoir différents types de clients : 

* des collectivités qui veulent améliorer leur information voyageur et leur système d'exploitation comme Poitiers avec Mecatran qui normalise leur flux temps réel custom afin d'homogénéiser les données des 40 communes, le département de l'Isère avec Citiway ou le Centre-Val-de-Loire avec Kisio 
* des opérateurs de transport comme Transdev, Keolis, Eole Mobilité etc. qui sous traitent traitent la production de leurs données à Pysae pour ou la SNCF qui passe par Kisio pour normaliser et avoir un contrôle qualité de leurs données 
* des stations de ski ou évènements ponctuels qui veulent avoir une information voyageur temps réel sur une courte durée voir de manière éphémère comme la [station de ski de Tignes avec Zenbus](https://transport.data.gouv.fr/datasets/horaires-theoriques-et-temps-reel-des-navettes-de-la-station-de-tignes-gtfs-gtfs-rt/)

<!--EndFragment-->

**La production et normalisation des données temps réel**

* Zenbus, Ubitransport et Pysae genère un flux sur le fonctionnement réel d’une exploitation de transport de voyageurs par rapport à une offre de transport théorique. Ces données servent à l'information voyageur et à la supervision des transports en commun pour les responsables d'exploitations. Elles sont produites grâce à des systèmes embarquées dans les véhicules.

  Production et diffusion des données temps réel par Pysae 

  ![](/images/captulkùre.png)

  source : [article de Pysae sur le temps réel ](https://web.pysae.com/blog/lom-et-ouverture-des-donnees-pour-le-transport-de-voyageurs)

Pysae ne produit que des données GTFS-RT tandis que Zenbus et Ubitransport produisent également des données au format SIRI et SIRI Lite. Ces deux services se basent sur le fichier théorique de leurs clients quand il existe ou produisent eux même le fichier GTFS. La génération des flux sortants par le serveur Zenbus est quasi instantanée avec une actualisation des données toutes les 3 secondes pour des véhicules qui roulent avec un terminal Android muni de l'application Zenbus Driver. 

* Kisio Digital, Cityway et Mecatran ne produisent pas de données mais les normalisent et les améliore à l'échelle locale comme régionale. Kisio Digital fournit, par exemple, les informations "Avance/retard" et "Perturbations" (météo, travaux, manifestation, déviation, interruption sur un tronçon etc.) ainsi que des interprétations pour proposer des itinéraires de remplacement au format GTFS-RT ou SIRI tandis que Mecatran fournit toutes les informations pouvant être contenues dans un flux GTFS-RT à leurs clients. 

**Les format de données fournis** 

Les producteurs de données interrogés fournissent majoritairement, voire exclusivement pour certains, des données temps réel au format GTFS-RT à leurs clients. Ces derniers utilisant déjà le GTFS pour leurs horaires théoriques, la correspondance avec le GTFS-RT est donc plus simple. 

Les données fournies par Mecatran sont à 90% en GTFS-RT. Leurs clients préfèrent ce format car il est spécifié et les informations obligatoires sont clairement définies contrairement au SIRI qui est autoporteur mais dont les contours ne sont pas définis. Cet éditeur de logiciel peut produire du SIRI mais n'a encore eu aucune demande. 



**Difficultés rencontrées lors de la production ou la normalisation des données** 





Les services de normalisation dépendant des données que leur transmettent les opérateurs de transport. La précision du flux normalisé dépend de la complétude des données fournis par les transporteurs. Par exemple, certains transporteurs renseignent la couleur des lignes de transport tandis que d'autres ne le font pas. Mais encore, il peut arriver que les données temps réel et théoriques ne soient pas fournies par le même éditeur ou producteur de données. Certaines informations essentielles comme les codes d'arrêts ne sont pas normalisées pareillement. Ils doivent donc faire un fichier de mapping pour faire une correspondance entre les arrêts et lignes. 

La difficulté principale repose donc sur l'absence de standard commun dans la qualité de renseignement des données dans le système d'aide à l'exploitation (SAE) et le fait qu'ils ne maitrisent pas la chaîne de bout en bout. De plus, les SAE sont d'abord des outils d'exploitation qui ne sont souvent pas utilisés par des personnes qui font de l'information voyageur. Les informations doivent donc être traitées, interprétées et réadaptées.

**Distribution des données temps réel**



Kisio Redistribue soit directement sur front (écran : gare, application mobile, Navitia WebSolution avec Widget qui permet d'embarquer IV sur des sites, API, SDK Navitia etc.) 



Mecatran : Parfois font contact avec les réutilisateurs pour leur fournir une URL quand les collectivités ne veulent pas avoir le contrôle sur toute la distribution de la donnée : interface producteurs / rédutilisateurs 



Kisio : Qualité données : >Sur théorique : Un gros contrôle qualité > correspond aux normes

TR : via les sondes où ils vont regarder si tout est ok au niveau des latences mais ne peuvent pas être sur place pour s’assurer que le bus passe bien

<!--EndFragment-->







Région avec différents opérateurs : ils les fusionnent pour avoir une seule API 

Dépendent d’API, de SAE ou de données pré existantes 

ont des logiciels qui peuvent créer de la donnée qui peuvent servir de SAE 

**problématiques : liées à identification avec données statiques**

Avantage/inconvénients GTFS-RT : couplage avec statique > pratique quand c’est bien fait car normalisé mais compliqué à mettre en oeuvre 

SIRI : couplage plus faible > format censé être suffisant en lui-même mais plus difficile à exploiter. Normes SIRI :

**Normes GTFS-RT : bien spécifié, bien indiqué quelles sont informations obligatoire, niveau d’informations attendues etc. hors SIRI : veut tout faire sans avoir vraiment de contours**

Techniquement : sous forme de flux brut (GTFS-RT avec les différentes variantes) soit API type rest (Geojson) plus axé pour les développeurs. Permet aux clients d’avoir accès à une plateforme pour contrôler l’accessibilité à ces données avec des clés pour avoir des statistiques de la réutilisation. Gérer clés API : qui accède et à quelle fréquence, contrats avec les réutilisateurs etc. 

\> Contractuellement : Client qui possède la donnée. font selon demande des clients : s' ils veulent redistribuer 

<!--EndFragment-->

Grand Poitiers : 

4 destinataires : 

Airweb : prestataire de solution numérique qui va gérer alimentation support numérique de Vitalis 

Modalis : partenaire qui va se servir du GTFS pour l’intégrer dans le référentiel Grande Aquitaine 

Grand Poitiers : sur sa plateforme locale 

**But : avoir un SAE unifié**



<!--EndFragment-->

<!--EndFragment-->

<!--EndFragment-->

<!--EndFragment-->

<!--EndFragment-->

<!--EndFragment-->

Interface avec SAE et récupère données des partenaires (prestataires données transport) : alimente Navitia qu’ils vont communiquer aux voyageurs. Flux qu’ils vont recevoir et vont interroger pour récupérer données TR 

Format normalisé 

Ont surtout sur GTFS-RT, SIRI de moins en moins. (Netex) 

<!--EndFragment-->

Communauté d'agglomération de l'Auxerrois :

Produisent du GTFS-RT : système de billettique et d’IV avait besoin de fonctionner sous GTFS, sont partis sur GTFS-RT pour pouvoir faire de l’OpenData 

Fait partenariat Transit (convention avec eux : contrat gratuit > ont des données anonymisés qui leur permettent de voir combien de personnes utilisent l’application et d’envoyer des alertes si besoin) et Google (GTFS format simple pour tester des fonctionnalités, on peut modifier facilement, format Européen très lourd/compliqué/permet pas itération/ pas capacité de le produire).

* avance/retard, prochains passages, position des véhicules, message d'informations et d'alertes ;

Implantés progressivement : pas un seul flux mais plusieur

Positions véhicules/ MAJ des trajets (avance/retard, prochains passafes) mais pas message d’informations et d’alertes. Ont des difficultés sur ce flux (message d’info’)

Transdev : produisent base GTFS à partir de Téo et leur envoie par mail > va sur G.Transit pour test qualité > publie sur le PAN 

Transdev créé leurs données mais Communauté qui met les données chez Google : Communauté a un contrôle de la donnée 

Flux automatisé : MAJ des trajets/positions des véhicules générés à partir du GPS d’un véhicule → Ubitransport se charge de transformer ce flux en GTFS-RT 

Avec Ubitransport : tablette tactile qui est connectée à un valideur et les personnes badgent dessus. Tablette utilisée par conducteur pour sélectionner sa course et avance/retard/ Tablette a également un GPS et dans le frontal Ubitransport ils peuvent suivre en TR avance/retard. Conversion information > GTFS-RT : option qu’ils avaient dans le marché avec Ubitransport

* Exprimer les éventuelles retombées positives de la production et publication des données. 

Augmentation du trafic (utilisation sur TransitApp) : usage a augmenté et il pense qu’ils passeront un cap décisif quand ils auront alerte 

Une fois qu’ils auront les alertes : cap décisif car voyageurs sauront que c’est du TR 



<!--EndFragment-->



[La loi d’orientation des mobilités (LOM) du 24 décembre 2019](https://www.cerema.fr/fr/actualites/lom-quelle-organisation-competences-mobilite#:~:text=G%C3%A9n%C3%A9ralisation%20de%20la%20comp%C3%A9tence%20d,ces%20dispositions%20de%20la%20LOM) a fixé un cadre législatif pour l’ouverture des données temps réel dans le domaine du transport de voyageurs en France. L’ouverture des données des services de transport de voyageurs vise à faciliter la mobilité, notamment via le concept du [MaaS (Mobility as a Service)](https://15marches.fr/mobilites/le-maas-en-questions).

![](https://assets.website-files.com/5ef534afcd35bac5a2a84fee/5fb629cf1f7f1bace50df24e_Sch%C3%A9ma%20saeiv%20PYSAE.PNG)

Schéma de la solution de SAEIV de PYSAE

# ‍**Les clients de PYSAE**

Les clients de [PYSAE ](https://web.pysae.com/)sont les opérateurs de transport de voyageurs et les collectivités (Autorité Organisatrice de la Mobilité ou AOM). PYSAE a pour client les grands groupes de transport de voyageurs : Keolis, Transdev et RATP et des opérateurs de transports locaux : [Avenir Atlantique](https://web.pysae.com/blog/saeiv-avenir-atlantique-nouvelle-aquitaine), Eole Mobilité, [SUMA](https://web.pysae.com/blog/transports-suma-cavalaire-sur-mer), etc.

![](https://assets.website-files.com/5ef534afcd35bac5a2a84fee/5ef60dc501e339c795e50c18_saeiv_schema.png)

Schéma d'un SAEIV



*

### [](https://pad.incubateur.net/KnNm3ZtDSgORWg3fw92XJg#Api-non-standards "Api-non-standards")Api non standards

## [](https://pad.incubateur.net/KnNm3ZtDSgORWg3fw92XJg#Services "Services")Services

cf. <https://transport.data.gouv.fr/real_time>

### [](https://pad.incubateur.net/KnNm3ZtDSgORWg3fw92XJg#Prochains-passages "Prochains-passages")Prochains passages

### [](https://pad.incubateur.net/KnNm3ZtDSgORWg3fw92XJg#Position-v%C3%A9hicules "Position-véhicules")Position véhicules

### [](https://pad.incubateur.net/KnNm3ZtDSgORWg3fw92XJg#Messages-d%E2%80%99alerte "Messages-d’alerte")Messages d’alerte

<!--EndFragment-->

<!--StartFragment-->

En général on peut faire un découpage fonctionnel des données temps réel.

### [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#Mise-%C3%A0-jour-des-horaires-de-passage "Mise-à-jour-des-horaires-de-passage")Mise à jour des horaires de passage

Pour *toutes* les désertes (`Trip` en GTFS / `VehicleJourney` en Transmodel) on a les nouveaux horaires de passage s’ils ont été modifiés.

C’est la donnée la plus exploitable pour les calculateurs d’itinéraires (à part Google qui préfére la position des véhicules, car ils peuvent en déduire la mise à jour des horaires).

### [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#Prochains-d%C3%A9parts "Prochains-départs")Prochains départs

Pour un arrêt on a les *n* prochains départ.

C’est un peu la version « pauvre » de la mise à jour des dessertes, circulation et horaires.\
Le gros souci de ces données c’est qu’il arrive très souvent qu’on ne puisse pas rattacher le prochain passage à la desserte théorique (« On sait qu’un bus passe dans 5min, mais on ne sait lequel c’est »). Du coup c’est très compliqué à prendre en compte de manière précise par les calculateurs d’itinéraires.\
De plus, certains services nécessitent un appel / arrêt ce qui génère beaucoup de charge serveur pour récupérer toutes les infos.

### [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#Alertes-de-services-messages "Alertes-de-services-messages")Alertes de services (messages)

Les alertes de services ou messages permettent de fournir des mises à jour en temps réel, chaque fois qu’il y a une interruption sur le réseau ou un problème à communiquer au voyageur, à l’aide de message.

Ca permet de faire passer des messages sans avoir à forcément préciser l’impact.

Dans certains cas les messages peuvent être restreints à un sous-ensemble des données (« la ligne 1 est en perturbée »), et sont souvent limités dans le temps.

### [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#Position-des-v%C3%A9hicules "Position-des-véhicules")Position des véhicules

Le plus précis (mais pas forcément le plus simple à prendre en compte pour les calculateurs d’itinéraires), en temps réel la position de tous les bus du réseau, c’est vraiment super pour que les utilisateurs voient où sont les bus qu’ils attendent.

a

#### [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#Services "Services")Services

Dans SIRI tout plein de services sont définis.\
Les principaux sont :

* `Stop Monitoring` (SM) (prochains passages)
* `Estimated Timetable` (ET) (mise à jour des horaires de passage)
* `General Message` (GM) (alertes de service)
* `Vehicle Monitoring` (VM) (position des véhicules)

Mais on en trouve plein d’autre :

* `Production Timetable`
* `Stop Timetable`
* `Connexion Timetable`
* `Connection Monitoring`
* `Facility Monitoring`

Les services défini sont sélectionnés avec les profils.\
Le truc qui est un peu compliqué c’est que SIRI ne s’arrètent pas à l’information voyageur, ca peut aussi être utilisé pour des données d’exploitation (d’où le nombre de services différents).

#### [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#Protocol-d%E2%80%99%C3%A9change1 "Protocol-d’échange1")Protocol d’échange

Contrairement au GTFS-RT, le protocol d’échange pour distribué les données est défini dans la norme et c’est du [SOAP](https://fr.wikipedia.org/wiki/SOAP).

Il peut être décliné en plusieurs versions (aussi définies par profil) avec accès sur demande ou sur abonnement, et tout plein de subtilités supplémentaires.

<https://enturas.atlassian.net/wiki/spaces/PUBLIC/pages/637370373/General+information+SIRI>

### [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#SIRI-Lite "SIRI-Lite")SIRI Lite

SIRI Lite est un sous dérivé de SIRI pour le rendre plus accessible, c’est uniquement les parties :

* `StopMonitoring` (prochains passages)
* `StopPointsDiscovery` / `LineDiscovery` (avoir des infos sur le réseau)
* `GeneralMessage` (alertes de service)

servi en `JSON` (au lieu de `XML`) par une API http classique (à la place de [SOAP](https://fr.wikipedia.org/wiki/SOAP)).

### [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#API-non-standard-de-temps-r%C3%A9el "API-non-standard-de-temps-réel")API non standard de temps réel

Il y a en plus de tout cela une Miryad d’API différentes, souvent sous forme d’API Rest (mais pas que), listées par <https://transport.data.gouv.fr/real_time>.

<!--EndFragment-->

# **Distribution des données temps réel pour l’information des voyageurs**

Chacun des clients de [PYSAE ](https://web.pysae.com/)dispose d’un flux [GTFS-RT](https://developers.google.com/transit/gtfs-realtime?hl=fr) avec les données temps réel de son exploitation.

[PYSAE ](https://web.pysae.com/)propose à ses clients deux niveaux tarifaires:

* Une formule « Standard » à 69€/mois/véhicule avec toute la solution SAEIV et un flux [GTFS-RT](https://developers.google.com/transit/gtfs-realtime?hl=fr) limité à 1 requête par minute
* Une formule « Entreprise » à 99€/mois/véhicule avec les fonctionnalités de la formule « Standard » et des fonctionnalités avancées et notamment une utilisation jusqu’à 600 requêtes par minute pour le flux GTFS-RT.

En complément l’offre de transport théorique (ou plan de transport) est accessible sur l’API de [PYSAE ](https://web.pysae.com/)au format [GTFS](<https://developers.google.com/transit/gtfs?hl=fr#:~:text=GTFS%20(General%20Transit%20Feed%20Specification,et%20les%20informations%20g%C3%A9ographiques%20associ%C3%A9es.>). Cette donnée est hébergée dans le [SAEIV ](https://web.pysae.com/blog/saeiv)et nécessaire à son fonctionnement. Elle peut être mise à jour depuis les interfaces utilisateurs de la solution [PYSAE ](https://web.pysae.com/)(configuration du plan de transport).

Les données générées par le [SAEIV ](https://web.pysae.com/blog/saeiv)de [PYSAE ](https://web.pysae.com/)sont la propriété intégrale de nos clients. L’utilisation des données en [GTFS-RT](https://developers.google.com/transit/gtfs-realtime?hl=fr) par exemple est donc soumise à l’accord de nos clients.

Le flux [GTFS-RT](https://developers.google.com/transit/gtfs-realtime?hl=fr) de [PYSAE ](https://web.pysae.com/)contient les informations suivantes:

* Course et véhicule concernés avec mise à jour du temps de passage aux arrêts (TripUpdate) ;
* Géolocalisation et statut du véhicule (VehiclePosition) ;
* Message d’information des voyageurs avec élément concerné et période d’application (Alert).

# **Difficultés pour la production de données temps réel**

La production de données temps réel de qualité nécessite selon nous 3 éléments:

1. Une solution de [SAEIV ](https://web.pysae.com/blog/saeiv)performante.
2. Des données d’offre théorique (plan de transport) précises et à jour : avec [PYSAE ](https://web.pysae.com/)et ses interfaces utilisateurs pour la configuration du plan de transport c’est rapide et facile à faire.
3. Un taux élevé de déclenchement des courses dans le [SAEIV ](https://web.pysae.com/blog/saeiv)par les conducteurs : avec [PYSAE ](https://web.pysae.com/)et son application que les conducteurs apprécient, l’adhésion au système est rapide et forte.

# **Bénéfices de la publication des données temps réel**

La publication des données en temps réel devient une obligation légale avec la [LOM](https://www.cerema.fr/fr/actualites/lom-quelle-organisation-competences-mobilite#:~:text=G%C3%A9n%C3%A9ralisation%20de%20la%20comp%C3%A9tence%20d,ces%20dispositions%20de%20la%20LOM).

L’ouverture de ces données doit permettre:

* Une intégration plus facile avec les applications [MaaS ](https://15marches.fr/mobilites/le-maas-en-questions)que mettent en place les villes moyennes et les régions.
* Une réutilisation des données par des services tiers.

Globalement, les enquêtes que nous avons réalisées auprès de voyageurs sur des lignes équipées de [PYSAE ](https://web.pysae.com/)ont montré que l’information en temps réel est une source de satisfaction importante et qu’elle peut conduire à une hausse de la fréquentation. Par exemple à Tulle, 64% des personnes interrogées ont dit prendre davantage le bus depuis que l’information en temps réel avait été mise en place.

<!--EndFragment-->

<!--EndFragment-->