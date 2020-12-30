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

* Kisio Digital, Cityway et Mecatran ne produisent pas de données mais les normalisent et les améliore à l'échelle locale comme régionale grâce notamment à des API harmonisés. Kisio Digital fournit, par exemple, les informations "Avance/retard" et "Perturbations" (météo, travaux, manifestation, déviation, interruption sur un tronçon etc.) ainsi que des interprétations pour proposer des itinéraires de remplacement au format GTFS-RT ou SIRI tandis que Mecatran fournit toutes les informations pouvant être contenues dans un flux GTFS-RT à leurs clients. 

**Les format de données fournis** 

Les producteurs de données interrogés fournissent majoritairement, voire exclusivement pour certains, des données temps réel au format GTFS-RT à leurs clients. Ces derniers utilisant déjà le GTFS pour leurs horaires théoriques, la correspondance avec le GTFS-RT est donc plus simple. 

Les données fournies par Mecatran sont à 90% en GTFS-RT. Leurs clients préfèrent ce format car il est spécifié et les informations obligatoires sont clairement définies contrairement au SIRI qui est autoporteur mais dont les contours ne sont pas définis. Cet éditeur de logiciel peut produire du SIRI mais n'a encore eu aucune demande. 

**Difficultés rencontrées lors de la production ou la normalisation des données** 

* Lorsque les données théoriques sont fournies par les clients, il peut y avoir des coordonnées géographiques qui ne sont pas valides. L'algorithme des producteurs étant sensible à la précision des données géographiques de référence, ils doivent mettre en place des outils permettant de les corriger. 

  Certains producteurs dépendent également des transporteurs, comme Pysae qui doit attendre le déclenchement des courses dans le SAEIV par les conducteurs. Les conducteurs doivent donc être réactifs. 
* Les services de normalisation dépendant des données que leur transmettent les opérateurs de transport : API (interface de programmation applicative), SAE, données préexistantes. La précision du flux normalisé dépend de la complétude des données fournis par les transporteurs. Par exemple, certains transporteurs renseignent la couleur des lignes de transport tandis que d'autres ne le font pas. Mais encore, il peut arriver que les données temps réel et théoriques ne soient pas fournies par le même éditeur ou producteur de données. Certaines informations essentielles comme les codes d'arrêts ne sont pas normalisées pareillement, les identifiants peuvent être différents etc. Ils doivent donc faire un fichier de mapping pour faire une correspondance entre les arrêts et lignes. 

La difficulté principale repose donc sur l'absence de standard commun dans la qualité de renseignement des données dans le système d'aide à l'exploitation (SAE) et le fait qu'ils ne maitrisent pas la chaîne de bout en bout. De plus, les SAE sont d'abord des outils d'exploitation qui ne sont souvent pas utilisés par des personnes qui font de l'information voyageur. Les informations doivent donc être traitées, interprétées et réadaptées.

**Distribution des données temps réel**

Les données fournies par les producteurs de données normalisées appartiennent aux clients. Ils permettent à leurs clients de contrôler l’accessibilité à ces données grâce à des clés pour accéder à leur API. Cela leur permet notamment d'avoir des statistiques sur le nombre et la fréquence de réutilisation. Certains redistribuent ces données à travers des interfaces comme des écrans dans les gares, des applications mobiles etc. ou des API comme Kisio. D'autres, comme Mecatran, entrent également directement en contact avec les réutilisateurs des données de leurs clients pour leur fournir une URL lorsque les clients ne veulent pas avoir le contrôle sur toute la distribution de leurs données. Zenbus met également à disposition les données de leurs clients directement sur le PAN, ce qui permet aux réutilisateurs de récupérer le flux de différents réseaux sur une seule plateforme. La communauté de l'Auxerrois récupère les données de son fournisseur pour les redistribuer ensuite sur le PAN. La collectivité renvoie tous leurs services de mobilité comme la billettique, leur service d'information voyageur vers [transport.data.gouv.fr](transport.data.gouv.fr) pour récupérer leurs données. 



**Contrôle qualité des données** 

Le contrôle qualité a surtout lieu au niveau des données théoriques. Certains producteurs, comme Kisio, installent des sondes leur permettant de mesurer le niveau de latence. D'autres comme Zenbus suivent le principe du “Eat your own dog food”, à savoir être les premiers utilisateurs de leurs données. Cela leur permet d'être confrontés à la qualité des données produites en étant des auditeurs permanents. 



<!--EndFragment-->



Grâce à la production des données temps réel, certaines collectivités comme la Communauté de l’Auxerrois ont constaté une augmentation de l'utilisation de leur application mobile, notamment grâce à un tableau de bord anonymisé leur permettant d'avoir des statistiques. 

Cette production et diffusion des données temps réel sur des portails à accès libre permet également aux Autorités Organisatrices de la Mobilité (AOM), à savoir l'autorité en charge de l’organisation du réseau de transport [](https://fr.wikipedia.org/wiki/Transports_urbains "Transports urbains")sur son territoire, d'être conforme à la réglementation. En effet, [la Loi d'Orientation des Mobilités](https://www.legifrance.gouv.fr/loda/id/JORFTEXT000039666574/2020-12-30/) (LOM) promulguée le 24 décembre 2019  a fixé un cadre législatif pour l’ouverture des données temps réel dans le domaine du transport de voyageurs en France. L’ouverture des données des services de transport de voyageurs vise à faciliter la mobilité, notamment via le concept du [MaaS (Mobility as a Service)](https://15marches.fr/mobilites/le-maas-en-questions).

<!--EndFragment-->





ouverture des données temps réel sur des









*



<!--EndFragment-->



[](https://www.cerema.fr/fr/actualites/lom-quelle-organisation-competences-mobilite#:~:text=G%C3%A9n%C3%A9ralisation%20de%20la%20comp%C3%A9tence%20d,ces%20dispositions%20de%20la%20LOM)



# ‍**Les clients de PYSAE**

Les clients de [PYSAE ](https://web.pysae.com/)sont les opérateurs de transport de voyageurs et les collectivités (Autorité Organisatrice de la Mobilité ou AOM). PYSAE a pour client les grands groupes de transport de voyageurs : Keolis, Transdev et RATP et des opérateurs de transports locaux : [Avenir Atlantique](https://web.pysae.com/blog/saeiv-avenir-atlantique-nouvelle-aquitaine), Eole Mobilité, [SUMA](https://web.pysae.com/blog/transports-suma-cavalaire-sur-mer), etc.

![](https://assets.website-files.com/5ef534afcd35bac5a2a84fee/5ef60dc501e339c795e50c18_saeiv_schema.png)

Schéma d'un SAEIV





### [](https://pad.incubateur.net/KnNm3ZtDSgORWg3fw92XJg#Prochains-passages "Prochains-passages")

### .

a

#### [](https://pad.incubateur.net/ZaYJvCIHQBGAr194xb_gXA#Services "Services")Services





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

# **Bénéfices de la publication des données temps réel**

La publication des données en temps réel devient une obligation légale avec la [LOM](https://www.cerema.fr/fr/actualites/lom-quelle-organisation-competences-mobilite#:~:text=G%C3%A9n%C3%A9ralisation%20de%20la%20comp%C3%A9tence%20d,ces%20dispositions%20de%20la%20LOM).

L’ouverture de ces données doit permettre:

* Une intégration plus facile avec les applications [MaaS ](https://15marches.fr/mobilites/le-maas-en-questions)que mettent en place les villes moyennes et les régions.
* Une réutilisation des données par des services tiers.

Globalement, les enquêtes que nous avons réalisées auprès de voyageurs sur des lignes équipées de [PYSAE ](https://web.pysae.com/)ont montré que l’information en temps réel est une source de satisfaction importante et qu’elle peut conduire à une hausse de la fréquentation. Par exemple à Tulle, 64% des personnes interrogées ont dit prendre davantage le bus depuis que l’information en temps réel avait été mise en place.

<!--EndFragment-->

<!--EndFragment-->