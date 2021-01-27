---
title: "La production des données temps réel pour les transports en commun "
date: 2020-12-23T09:33:17.115Z
tags:
  - retour d'expérience
description: >+
  Cet article a été réalisé à partir d'interviews effectuées auprès de
  collectivités, producteurs et services de traitement de données temps-réel
  afin de mieux comprendre les enjeux de production et de diffusion de ces
  données. 


images:
  - /images/logo_zenbus_officiel.png
---
Cet article permet d'une part de connaître les différents formats de données supportés par le Point d'Accès National pour la diffusion de données temps-réel. 

D'autre part, de mieux comprendre les enjeux autour de la production et la diffusion de ces données : 

* Pour qui sont produites ces données ;
* Comment sont elles produites ;
* Sous quels formats sont elles normalisées ;
* Quelles sont les principales difficultés rencontrées lors de la production de ces données ; 
* Comment sont-elles redistribuées aux clients ;
* Comment les producteurs évaluent la qualité de leurs données. 

- - -

[transport.data.gouv.fr ](transport.data.gouv.fr)est le point d'accès national (PAN) aux données mobilité. La plateforme a pour mission de rassembler l'ensemble des données servant à l'information voyageur dans des formats harmonisés et sans obligation d'authentification pour les réutilisateurs. Cette ouverture des données vise à faciliter les déplacements des citoyens par l'intégration de ces données dans des services tiers comme des calculateurs d'itinéraires, des cannes connectées, des bureaux d'aménagement du territoire etc. On retrouve cette diversité de service servant à l'information voyageur dans les réutilisateurs du PAN.

![](/images/capturmmme.png)

 *Réutilisateurs au 30.12.2020*

- - -

Il existe **trois niveaux de fraîcheur** pour les données relatives aux transports : 

* **les horaires théoriques :** horaires prévisionnels diffusés sous forme d'heure ou de fréquence de passage. 
* **les horaires adaptés :** modifications des horaires théoriques lorsqu'il y a des évènements modifiant les horaires et/ou itinéraires des véhicules. Certains producteurs produisent un plan de transport mise à jour en cas de grève ou de changements majeurs sur les horaires théoriques initialement transmis. Ces données peuvent prendre la forme d'un nouveau GTFS complet, simplement mis à jour, ou bien d'un "patch". Le patch correspond à un nouveau GTFS limité aux journées impactées. Ces horaires ne peuvent toutefois pas être considérés comme étant en temps-réel mais permettent d'avoir une meilleure information voyageur simplement
* **les horaires temps réel :** état du trafic à l'instant. 

Cet article traitera exclusivement des données temps-réel pour les transports en commun. 

Ces données sont diffusés par le PAN dans la tuile "[Temps réel transport en commun](https://transport.data.gouv.fr/datasets?type=public-transit&filter=has_realtime)". 

<!--EndFragment-->

- - -

# Les données temps réel : de la production à la diffusion

Les données temps réel permettent de fournir une information voyageur qui reflète la réalité du terrain. Ces données peuvent servir à la fois à la gestion de l’exploitation et à l’information des voyageurs. Cette information voyageur permet aux calculateurs d'itinéraires d'optimiser le temps de trajet de leurs usagers. Seules les informations servant à l'informations voyageur sont publiques. Elles permettent à un usager d'être notifié si son bus a du retard, si il y a des déviations à certains arrêts pour cause de travaux etc. Pour ce faire, il existe trois formats harmonisés et supportés par le PAN afin de modéliser cette information : 

* **Le GTFS-RT (General Transit Feed Specification - realtime)**

C'est un standard conçu par Google mais qui est désormais maintenu de manière communautaire sous l'égide de MobilityData.

Ce format permet de récupérer toutes les données temps réel d'un réseau en une requête. 

 Ce flux temps réel peut contenir trois types d'information : 

* `TripUpdate` qui correspond à la mise à jour des horaires de passage
* `Alert` qui génère des alertes de service
* `VehiclePositions` qui renseigne la position des véhicules

Certains producteurs proposent toutes ces informations dans un seul flux, comme [Zenbus](https://transport.data.gouv.fr/datasets?_utf8=%E2%9C%93&q=zenbus), tandis que d'autres préfèrent avoir un flux par type d'information. C'est le cas pour la [Communauté de l’Auxerrois](https://transport.data.gouv.fr/datasets/reseau-de-transports-en-commun-de-la-communaute-dagglomeration-de-lauxerrois/) qui a publié un flux pour `TripUpdate`et un autre pour `VehiclePositions`.

![](/images/capturemls.png)

Le **GTFS-RT** **doit être accompagné d'un fichier théorique au format GTFS** pour pouvoir être utilisé. Ces données ne sont pas donc pas **autoporteuses**.\
Par exemple, pour les données de mise à jour des horaires (`TripUpdate`), pour un `Trip` donné on a la mise à jour de ses horaires pour la journée, mais pas d'informations concernant la `Route` de ce `Trip` ni la position des arrêts. Ces informations sont fournis dans le GTFS. 

* **Le SIRI (Service Interface for Realtime Information)**

Le SIRI est une norme définie par le Comité Européen de Normalisation et correspond à la norme [NeTEx](http://netex-cen.eu/) pour le temps réel. Elle caractérise des services temps réel dont les principaux sont : 

* `Stop Monitoring` qui affiche les prochains passages
* `Estimated Timetable` qui met à jour des horaires de passage
* `General Message` qui génère des alertes de service
* `Vehicle Monitoring` qui renseigne la position des véhicules

Les données sont transmises via le protocole [SOAP](https://fr.wikipedia.org/wiki/SOAP), à la demande (en mode `PULL`) ou sur abonnement (en mode `PUSH`)

Tout comme le NeTEx, un profil doit être défini. C'est un **format autoporteur** mais les données peuvent ne **pas interopérables entre les profils** lorsqu'ils ont des services définis différents. 

* **Le SIRI Lite**

Le SIRI Lite est un sous dérivé de SIRI qui ne contient que les informations suivantes afin de le rendre plus accessible : 

* `StopMonitoring` qui affiche les prochains passages
* `StopPointsDiscovery` / `LineDiscovery` qui fournit des informations sur le réseau
* `GeneralMessage`  qui génère des alertes de service

les données sont servies via une API http classique dans le format JSON

<!--EndFragment-->

- - -

La production et diffusion des données temps réel en GTFS-RT, SIRI et SIRI Lite sur des portails à accès libre permettent aux Autorités Organisatrices de la Mobilité (AOM) d'être conforme au cadre juridique défini notamment par l'article 25 de [la Loi d'Orientation des Mobilités](https://www.legifrance.gouv.fr/loda/id/JORFTEXT000039666574/2020-12-30/) (LOM) promulguée le 24 décembre 2019. Cet article fixe un cadre législatif pour l’ouverture des données temps servant à l'information voyageur. L'ouverture de ces données étant attendu au 1er décembre 2020. 

- - -

**Les clients des producteurs de données temps réel** 

Les producteurs de données temps-réel peuvent avoir différents types de clients : 

* **des collectivités** qui veulent améliorer leur information voyageur et leur système d'exploitation comme le département de l'Isère avec Citiway, le Centre-Val-de-Loire avec Kisio Digital ou le Grand Poitiers avec Mecatran. Ce dernier normalise leur flux temps réel custom afin d'homogénéiser à terme les données des 40 communes
* **des opérateurs** de transport comme Transdev, Keolis, Eole Mobilité etc. qui sous traitent la production de leurs données à Pysae ou la SNCF qui passe par Kisio pour normaliser et avoir un contrôle qualité de leurs données 
* **des stations de ski ou évènements ponctuels** qui veulent avoir une information voyageur temps réel sur une courte durée voir de manière éphémère comme la [station de ski de Tignes avec Zenbus](https://transport.data.gouv.fr/datasets/horaires-theoriques-et-temps-reel-des-navettes-de-la-station-de-tignes-gtfs-gtfs-rt/)

- - -

**Production et normalisation des données temps réel**

* **Ubitransport, Zenbus et Pysae** génèrent un flux sur le fonctionnement réel d’une exploitation de transport de voyageurs par rapport à une offre de transport théorique. Ces données servent à l'information voyageur et à la supervision des transports en commun pour les responsables d'exploitations. Elles sont produites grâce à des systèmes embarquées dans les véhicules.

![](/images/schema-1-.png "Production et diffusion des données temps réel par Pysae")

source : [](https://web.pysae.com/blog/lom-et-ouverture-des-donnees-pour-le-transport-de-voyageurs)Zenbus

* **Pysae** ne produit que des données GTFS-RT tandis que **Zenbus et Ubitransport** produisent également des données au format SIRI et SIRI Lite. Ces deux services se basent sur le fichier théorique de leurs clients quand il existe ou produisent eux même le fichier GTFS. 
* **Kisio Digital, Cityway et Mecatran** ne produisent pas de données mais les normalisent et les améliorent à l'échelle locale comme régionale. Kisio Digital fournit, par exemple, les informations "Avance/retard" et "Perturbations" (météo, travaux, manifestation, déviation, interruption sur un tronçon etc.) ainsi que des itinéraires de remplacement prenant en compte les informations temps réel tandis que Mecatran fournit toutes les informations pouvant être contenues dans un flux GTFS-RT à leurs clients

- - -

**Formats de données fournis** 

Les producteurs de données interrogés fournissent majoritairement, voire exclusivement pour certains, des données temps réel au format GTFS-RT à leurs clients. Ces derniers utilisant déjà le GTFS pour leurs horaires théoriques, la correspondance avec le GTFS-RT est donc plus simple. 

Les données fournies par Mecatran sont à 90% en GTFS-RT. Leurs clients préfèrent ce format car il est spécifié et les informations obligatoires sont clairement définies contrairement au SIRI qui est autoporteur mais dont les contours ne sont pas définis. Cet éditeur de logiciel peut produire du SIRI mais n'a encore eu aucune demande. 

- - -

**Difficultés rencontrées lors de la production ou la normalisation des données** 

* Lorsque les données théoriques sont fournies par les clients, il peut y avoir des coordonnées géographiques qui ne sont pas valides. L'algorithme des producteurs étant sensible à la précision des données géographiques de référence, ils doivent mettre en place des outils permettant de les corriger. 

  Certains producteurs dépendent également des transporteurs, comme Pysae et Ubitransport qui doivent attendre le déclenchement des courses dans le SAEIV par les conducteurs. 
* Les services de normalisation dépendent des données que leur transmettent les opérateurs de transport : API (interface de programmation applicative), SAE, données préexistantes. La précision du flux normalisé découle de la complétude des données fournis par les transporteurs. Par exemple, certains transporteurs renseignent la couleur des lignes de transport tandis que d'autres ne le font pas. Mais encore, il peut arriver que les données temps réel et théoriques ne soient pas fournies par le même éditeur ou producteur de données. Certaines informations essentielles comme les codes d'arrêts ne sont pas normalisées pareillement, les identifiants peuvent être différents etc. Ils ne maitrisent pas la chaîne de bout en bout et doivent donc faire un fichier de mapping pour avoir une correspondance entre les arrêts et les lignes. 

La difficulté principale repose sur l'absence de standard commun dans la qualité de renseignement des données dans le système d'aide à l'exploitation (SAE). De plus, les SAE sont des outils d'exploitation qui ne sont souvent pas utilisés par des personnes qui font de l'information voyageur. Les informations doivent donc être traitées, interprétées et réadaptées.

- - -

**Distribution des données temps réel**

Les données fournies par les producteurs de données normalisées appartiennent aux clients. Ils permettent à leurs clients de contrôler l’accessibilité à ces données grâce à des clés pour accéder à leur API. Cela leur permet notamment d'avoir des statistiques sur le nombre de réutilisateurs et la fréquence de réutilisation. Certains redistribuent ces données à travers des interfaces comme des écrans dans les gares, des applications mobiles, des sites internet de transport etc. ou des API (Application Programming Interface) et SDK (Software Development Kit) comme [www.navitia.io](http://www.navitia.io/) de Kisio Digital pour permettre à d’autres de développer des services numériques pour les citoyens et d’innover en utilisant ces mêmes données. 



D'autres, comme Mecatran, entrent aussi en contact avec les réutilisateurs des données de leurs clients pour leur fournir une URL lorsque les clients ne veulent pas avoir le contrôle sur toute la distribution de leurs données. Zenbus met également à disposition les données de leurs clients directement sur le PAN, ce qui permet aux réutilisateurs de récupérer le flux de différents réseaux sur une seule plateforme. La communauté de l'Auxerrois récupère les données de leur fournisseur, Ubitransport, pour les redistribuer ensuite sur le PAN. La communauté de l'Auxerrois renvoie tous leurs services de mobilité comme la billettique, leur service d'information voyageur vers[ leurs données publiées transport.data.gouv.fr](https://transport.data.gouv.fr/datasets/reseau-de-transports-en-commun-de-la-communaute-dagglomeration-de-lauxerrois/) pour les récupérer. 

- - -

**Contrôle qualité des données** 

Le contrôle qualité a surtout lieu au niveau des données théoriques. Certains producteurs, comme Kisio Digital, installent des sondes qui leur permettent de mesurer le niveau de latence. D'autres comme Zenbus suivent le principe du “Eat your own dog food”, à savoir être les premiers utilisateurs de leurs données. Cela leur permet d'être confrontés à la qualité des données produites en étant des auditeurs permanents. 

- - -

Grâce à la production des données temps réel, certaines collectivités comme la Communauté de l’Auxerrois ont constaté une augmentation de l'utilisation de leur application mobile. L'ouverture de ces données permet également aux producteurs d'améliorer la qualité de leurs services. Des réutilisateurs de données de Zenbus comme Cityway ou Mybus leur font des retours d'expérience leur permettant d'adapter les informations qu'ils fournissent à leurs besoins. 

### [](https://pad.incubateur.net/KnNm3ZtDSgORWg3fw92XJg#Prochains-passages "Prochains-passages")

- - -

- - -

Cet article a été rédigé grâce aux retours d'expériences des collectivités, producteurs et services de traitement de données temps-réel suivants : 

*Producteurs* 

* **[Zenbus](https://www.data.gouv.fr/fr/organizations/zenbus/), Olivier Deschaseaux co-fondateur en charge des partenariats, du marketing et de la communication.**\
  Services de géolocalisation temps réel à partir de smartphones et[ production de données temps réel dans des formats normalisés](https://zenbus.fr/LOM.pdf) (GTFS-RT et SIRI)
* **[Ubitransport](https://www.ubitransport.com/)**, Alexandre Cabanis Direction Marketing\
  Solutions intelligentes pour optimiser les réseaux de transport public : billetique / monétique, SAEIV et data 
* **[Kisio](https://kisio.com/) : Betrand Billoud et Laetitia Paternoster**\
  Service d'accompagnement des acteurs de la mobilité pour créer,\
  déployer et animer les services à la mobilité.
* **[City Way](https://www.data.gouv.fr/fr/organizations/cityway/), Nely Escoffier Responsable centrale de mobilité *[Itinisère](https://www.itinisere.fr/)***\
  Entreprise spécialisée dans le traitement des systèmes d’informations multimodaux (SIM) et la mise en œuvre de solutions numériques depuis une vingtaine d’année
* **[Mecatran](https://www.data.gouv.fr/fr/organizations/mecatran/), Laurent Grégoire directeur technique et Nicolas Taillade directeur de la sociét**é\
  Editeur de logiciel pour les transporteurs publiques pour l'amélioration, la normalisation et l'intégration de données statiques, temps réel et conjecturelles 
* **[Pysae](https://web.pysae.com/), Maxime Cabanel Responsable grands comptes** \
  [Solution pour système d'aide à l'exploitation et à l'information voyageurs (SAEIV)](https://web.pysae.com/blog/lom-et-ouverture-des-donnees-pour-le-transport-de-voyageurs) clé en main pour les conducteurs de bus, les exploitants et les voyageurs. 

*Collectivités* 

* **[Grand Poitiers](https://transport.data.gouv.fr/datasets?_utf8=%E2%9C%93&q=grand+poitiers), Nicolas Madignier gestionnaire de la data Mobilité Transport et du développement numérique à la Direction Mobilités**
* **[Communauté de l’agglomération de l'Auxerrois](https://transport.data.gouv.fr/datasets/reseau-de-transports-en-commun-de-la-communaute-dagglomeration-de-lauxerrois/), François Meyer chef du service mobilité**