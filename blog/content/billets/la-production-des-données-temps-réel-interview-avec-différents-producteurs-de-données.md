---
title: "La production des données temps réel pour les transports en commun "
date: 2020-12-23T09:33:17.115Z
tags:
  - retour d'expérience
description: >-
  Interview avec différents producteurs de données temps réel et services de
  traitement de ces données afin de mieux comprendre les enjeux autour de la
  production des données temps réel 



  Zenbus : 

  Kisio Digital : Betrand Billoud et Laetitia Paternoster 

  Pysae : 

  City Way : Nely Escoffier 

  Mecatran : 

  Ubitransport 


  Nous nous sommes également entretenus avec des collectivités ayant publié leurs données sur le Point d'Accès National (PAN)

  Grand Poitiers : Nicolas Madignier 

  Communauté de l’agglomération de l'Auxerrois : François Meyer
---
<!--StartFragment-->



transport.data.gouv.fr a pour objectif de rassembler l'ensemble des données servant à l'information voyageur dans des formats harmonisés et sans obligation d'authentification pour les réutilisateurs. Cette ouverture des données vise à faciliter les déplacements des citoyens par l'intégration de ces données dans des services tiers. 

\[Mettre capture d'écran des réutilisateurs]



Il existe trois niveaux de fraîcheur pour les données relatives aux transports : 

* les horaires théoriques : horaires prévisionnels diffusés sous forme d'heure ou de fréquence de passage. 
* les horaires adapté : les horaires théoriques peuvent être modifiés lorsqu'il y a des évènements modifiant les horaires et/ou itinéraires des véhicules. Par exemple, la RATP diffuse un plan de transport mise à jour en cas de grève, la SNCF livre un patch lorsqu'il y a des changements majeurs sur les horaires théoriques initialement transmis. Ces horaires ne peuvent toutefois pas être considérés comme étant en temps-réel. 
* les horaires temps réel : les horaires affichés correspondent à l'état du trafic à l'instant. 

Cet article traitera exclusivement des horaires temps-réel. 



Les données temps réel permettent de fournir une information voyageur qui reflète la réalité du terrain. Elles permettent ainsi à un usager d'être notifié si son bus a du retard par exemple, si il y a des déviations à certains arrêts pour des travaux etc. Pour ce faire, il existe trois formats harmonisés et supportés par le PAN afin de modéliser cette information : 

* **Le GTFS-RT (General Transit Feed Specification - realtime)**

C'est un standard conçu par Google mais qui est désormais maintenu par une communauté (à completer). 

C'est un un format binaire compact (protobuf) qui utilise une méthode globale permettant de récupérer toutes les données d'un réseau en une requête. 

 Ce flux temps réel peut contenir trois types d'information : 

* `TripUpdate` qui correspond à la mise à jour des horaires de passage
* `Alert`  qui genère des alertes de service
* `VehiclePositions` qui renseigne la position des véhicules

Certains flux proposent toutes ces informations dans un seul flux, comme [Zenbus](https://transport.data.gouv.fr/datasets?_utf8=%E2%9C%93&q=zenbus), mais certains producteurs préfèrent avoir un flux par type de données. C'est le cas pour la [Communauté de l’Auxerrois](https://transport.data.gouv.fr/datasets/reseau-de-transports-en-commun-de-la-communaute-dagglomeration-de-lauxerrois/) qui a publié un flux pour `TripUpdate`et un autre pour `VehiclePositions`



![](/images/capturemls.png)

Il doit être accompagné d'un fichier théorique au format GTFS pour pouvoir être utilisé. Ces données ne sont pas donc pas autoporteuses.\
Par exemple pour les données de mise à jour des horaires (`TripUpdate`), pour un `Trip` donné on a la mise à jour de ses horaires pour la journée, mais pas d'informations concernant la `Route` de ce `Trip` ni la position des arrêts.

* SIRI (Service Interface for Realtime Information)

Le SIRIest une normedéfinie par le Comité Européen de Normalisation et correspond à la norme Netex pour le temps réel. Elle caractérise des services temps réel dont les principaux sont : 

* `Stop Monitoring` qui affiche les prochains passages
* `Estimated Timetable` qui met à jour des horaires de passage)
* `General Message` qui génère des alertes de service
* `Vehicle Monitoring` qui renseigne la position des véhicules



Tout comme le Netex, un profil doit être défini. C'est un format autoporteur mais les données ne sont pas interopérables entre les profils car les services définis sont sélectionnées avec les profils.

### [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#SIRI-Lite "SIRI-Lite")SIRI Lite

SIRI Lite est un sous dérivé de SIRI pour le rendre plus accessible, c’est uniquement les parties :

* `StopMonitoring` (prochains passages)
* `StopPointsDiscovery` / `LineDiscovery` (avoir des infos sur le réseau)
* `GeneralMessage` (alertes de service)

servi en `JSON` (au lieu de `XML`) par une API http classique (à la place de [SOAP](https://fr.wikipedia.org/wiki/SOAP)).





Important de bien inclure une clause sur l’ouverture des données dans vos contrats publics avec des transporteurs ou SAEIV.\
Vous pouvez exiger l’ouverture des données, et préciser un format auquel ces données doivent être produits.\
Dans une logique de maîtrise des coûts, nous recommandons de produire un flux au format GTFS-RT.\
Produire et diffuser des données au format GTFS-RT est moins cher que produire et diffuser des données au format SIRI.\
L’équipe transport.data.gouv.fr a produit un convertisseur GTFS-RT vers SIRI-Lite. On estime que si vous avez publié un flux au format GTFS-RT, la conversion vers le SIRI-Lite est assurée par nos outils, et vous êtes en conformité avec vos obligations réglementaires.\
Le réutilisateur pourra choisir directement s’il préfère réutiliser le flux GTFS-RT ou SIRI-Lite. 

Exemples: voir les clauses de DSP de Lille Métropole (MEL). 





<!--StartFragment-->

[La loi d’orientation des mobilités (LOM) du 24 décembre 2019](https://www.cerema.fr/fr/actualites/lom-quelle-organisation-competences-mobilite#:~:text=G%C3%A9n%C3%A9ralisation%20de%20la%20comp%C3%A9tence%20d,ces%20dispositions%20de%20la%20LOM) a fixé un cadre législatif pour l’ouverture des données temps réel dans le domaine du transport de voyageurs en France. L’ouverture des données des services de transport de voyageurs vise à faciliter la mobilité, notamment via le concept du [MaaS (Mobility as a Service)](https://15marches.fr/mobilites/le-maas-en-questions).

# **La solution PYSAE**

[PYSAE ](https://web.pysae.com/)facilite le quotidien des conducteurs et des responsables d’exploitation et les aide à fournir un service de meilleure qualité aux voyageurs en développant une solution de [SAEIV ](https://web.pysae.com/blog/saeiv)(Système d’Aide à l’Exploitation et d’Information des Voyageurs) hébergée et facile à déployer (SaaS).

![](https://assets.website-files.com/5ef534afcd35bac5a2a84fee/5fb629cf1f7f1bace50df24e_Sch%C3%A9ma%20saeiv%20PYSAE.PNG)

Schéma de la solution de SAEIV de PYSAE

# ‍**Les clients de PYSAE**

Les clients de [PYSAE ](https://web.pysae.com/)sont les opérateurs de transport de voyageurs et les collectivités (Autorité Organisatrice de la Mobilité ou AOM). PYSAE a pour client les grands groupes de transport de voyageurs : Keolis, Transdev et RATP et des opérateurs de transports locaux : [Avenir Atlantique](https://web.pysae.com/blog/saeiv-avenir-atlantique-nouvelle-aquitaine), Eole Mobilité, [SUMA](https://web.pysae.com/blog/transports-suma-cavalaire-sur-mer), etc.

# **Production de données**

Comme tous les [SAEIV](https://web.pysae.com/blog/saeiv), [PYSAE ](https://web.pysae.com/)génère des données sur le fonctionnement réel d’une exploitation de transport de voyageurs par rapport à une offre de transport théorique (aussi appelée plan de transport). Les données générées peuvent servir à la gestion de l’exploitation et à l’information des voyageurs en temps réel.

Les données temps réel pour l’information des voyageurs correspondent à:

* La géolocalisation des véhicules circulant sur une course ;
* Le temps d’arrivée prévu aux arrêts ;
* Les messages d’information des voyageurs.

Les données d’exploitation sont confidentielles. Les données pour l’information des voyageurs peuvent être ouvertes au public.

# **Méthode de production des données**

![](https://assets.website-files.com/5ef534afcd35bac5a2a84fee/5ef60dc501e339c795e50c18_saeiv_schema.png)

Schéma d'un SAEIV

La solution [PYSAE ](https://web.pysae.com/)s’appuie sur une application Android sur smartphone ou tablette pour l’aide à la conduite à destination des conducteurs de bus et de cars. Sur cette application les conducteurs disposent des informations utiles pour réaliser leurs missions dans les meilleures conditions avec notamment le guidage GPS par rapport à l’itinéraire de la course et les informations d’avance-retard par rapport aux horaires. Avec son application le conducteur est également en contact permanent avec le poste central d’exploitation. L’application d’aide à la conduite peut être connectée à d’autres équipements embarqués dans le véhicule comme la girouette ou la billettique.

L’application d’aide à la conduite remonte également en permanence les données aux serveurs de [PYSAE ](https://web.pysae.com/)sur la circulation du véhicule. Les serveurs [SAEIV ](https://web.pysae.com/blog/saeiv)stockent et diffusent cette information aux services consommateurs adéquats.

Les données temps réel produites par le [SAEIV ](https://web.pysae.com/blog/saeiv)de [PYSAE ](https://web.pysae.com/)sont le résultat de la comparaison entre l’offre théorique (plan de transport) et les données du terrain. Les utilisateurs de PYSAE peuvent importer leurs données d’offre théorique dans les formats suivants : [GTFS](<https://developers.google.com/transit/gtfs?hl=fr#:~:text=GTFS%20(General%20Transit%20Feed%20Specification,et%20les%20informations%20g%C3%A9ographiques%20associ%C3%A9es.>), Excel, Transdev-TEO, Keolis-Okapi et[ Gescar-GTFS](https://www.perinfo.eu/).  Ils peuvent également saisir ou modifier ces données directement dans PYSAE via les interfaces utilisateurs pour la configuration du plan de transport.



<!--StartFragment-->

Quel surcoût pour mettre en place le temps réel?

Deux méthodes :

* temps réel unitaire : typiquement pou les bus pour afficher le passage du prochain bus. Le problème c’est que tu pas relier ce bus à une donnée théorique. Pour les calculateurs d’itinéraires c’est très limité.
* temps réel global : où tu récupères toutes les données de ton réseau où tu peux préciser quel bus passe. Le GTFS-RT par exemple ne fait que du global. Tu fais une requête qui t’envoies un fichier compressé qui permet de retrouver quel bus passe. Le GTFS RT doit être couplé avec des données théoriques.

3 niveaux de fraîcheurs :

* théorique
* temps-réel
* adapté : tous les matins la RATP redonne un nouveau plan de transport mis à jour en cas de besoin. Ca permet de gérer des grèves. Mais c’est pas du temps-réel. Les petits ont pas forcément les outil pour faire ça. La SNCF par exemple livre un patch. Toulouse par exemple diffuse un réseau tous les jours.

## [](https://pad.incubateur.net/KnNm3ZtDSgORWg3fw92XJg#Formats "Formats")Formats

### [](https://pad.incubateur.net/KnNm3ZtDSgORWg3fw92XJg#GTFS-RT "GTFS-RT")GTFS-RT

Requêtes globales. Les infos transitent par fichier binaire très compressé.

### [](https://pad.incubateur.net/KnNm3ZtDSgORWg3fw92XJg#Siri "Siri")Siri

Requêtes globales et/ou requêtes unitaires. API SOAP.

### [](https://pad.incubateur.net/KnNm3ZtDSgORWg3fw92XJg#Siri-lite "Siri-lite")Siri lite

Dérivé de SIRI. API REST. Plus simple à utiliser. Expose que les API unitaires du SIRI.

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

## [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#Formats-de-donn%C3%A9es "Formats-de-données")Formats de données

### [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#GTFS-RT "GTFS-RT")GTFS-RT

General Transit Feed Specification – realtime

**Standard** conçu par Google (au départ c’était Google Transit Feed Specification), puis lâché et maintenu maintenant par une communauté.

Le GTFS-RT contient que des données, dans un format binaire compact (protobuf), sans préciser le protocole de transport de la donnée (qui est en général du http).

Les données GTFS-RT ne sont pas autoporteuses, elles nécessitent les données GTFS pour pouvoir être utilisées.\
Par exemple pour les données de mise à jour des horaires (`TripUpdate`), pour un `Trip` donné on a la mise à jour de ses horaires pour la journée, mais on n’a pas l’info concernant la `Route` de ce `Trip` ni la position des arrêts.

Processus de modification clair et ouvert.

Pull request sur le repo Github + annonce sur une mailing liste. 7 jours plus tard on peut demander un vote. On doit avoir 3 oui, dont 1 producteur de données et 1 réutilisateur et pas de véto. Si véto la proposition peut être modifiée et re proposée au vote.

GTFS-RT peut contenir 3 types de données :

* `TripUpdate` (mise à jour des horaires de passage)
* `Alert` (alertes de service)
* `VehiclePositions` (position des véhicules)

Certains flux proposent toutes les infos dans le flux mais certains producteurs préfèrent avoir 1 flux par type de données.

#### [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#Protocol-d%E2%80%99%C3%A9change "Protocol-d’échange")Protocol d’échange

Le protocol d’échange pour distribuer les données n’est pas défini dans le standard, mais comme les données sont d’un bloc et dans un format très compact, c’est souvent distribué par un serveur http comme un simple fichier protobuf.

### [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#SIRI "SIRI")SIRI

Service Interface for Realtime Information

**Norme** définie par le Comité Européen de Normalisation.

C’est le pendant temps réel de la norme [NeTEx](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA).

Basé sur [Transmodel](http://www.transmodel-cen.eu/), une modélisation des données différente de celle utilisée par GTFS (et plus complète).

SIRI défini des **Services** temps réel (et non pas directement des données).

Tout comme [NeTEx](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA) il faut définir un profil sur la norme. Ce profil correspond au sous-ensemble de la norme qui va être utilisé. Le problème de cette notion de profil c’est que ça rend les données non interopérables entre les profils.

En faisant parti du [CEN](https://www.cen.eu/Pages/default.aspx) l est possible de participer à l’évolution de la norme, mais le processus d’évolution est beaucoup plus lent que celui de GTFS-RT.

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
* `Connection Monitoring `
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