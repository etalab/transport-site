---
title: "La production et diffusion de données temps-réel pour les transports en
  commun "
date: 2020-12-31T11:33:14.621Z
tags:
  - retour d'expérience
description: "Interview avec des collectivités, différents producteurs et
  services de traitement de données temps réel afin de mieux comprendre les
  enjeux autour de la production et la diffusion de ces données. "
images:
  - /images/logo_zenbus_officiel.png
---


**Personnes interviewées** 

Producteurs 

* [Zenbus](https://www.data.gouv.fr/fr/organizations/zenbus/), Olivier Deschasseaux co-fondateur en charge des partenariats, du marketing et de la communication

Services de géolocalisation temps réel à partir de smartphones et production de données temps réel dans des formations normalisés (GTFS-RT et SIRI)

* [ Pysae](https://web.pysae.com/), Maxime Cabanel Responsable grands comptes 

Solution pour système d'aide à l'exploitation et à l'information voyageurs (SAEIV) clé en main pour les conducteurs de bus, les exploitants et les voyageurs. 

* [Ubitransport](https://www.ubitransport.com/), Alexandre Cabanis Direction Marketing

Solution pour système d'aide à l'exploitation et à l'information voyageurs (SAEIV) 

* [Kisio](https://kisio.com/) : Betrand Billoud et Laetitia Paternoster

Service d'accompagnement des acteurs de la mobilité pour créer,\
déployer et animer les services à la mobilité.

* [City Way](https://www.data.gouv.fr/fr/organizations/cityway/), Nely Escoffier Responsable centrale de mobilité *[Itin**isère**](https://www.itinisere.fr/)*

Entreprise spécialisée dans le traitement des systèmes d’informations multimodaux (SIM) et la mise en œuvre de solutions numériques depuis une vingtaine d’année

* [Mecatran](https://www.data.gouv.fr/fr/organizations/mecatran/), Laurent Grégoire directeur technique et Nicolas Taillade directeur de la société

Editeur de logiciel pour les transporteurs publiques pour l'amélioration, la normalisation et l'intégration de données statiques, temps réel et conjecturelles 

Collectivités 

* [Grand Poitiers](https://transport.data.gouv.fr/datasets?_utf8=%E2%9C%93&q=grand+poitiers), Nicolas Madignier gestionnaire de la data Mobilité Transport et du développement numérique à la Direction Mobilités
* [Communauté de l’agglomération de l'Auxerrois](https://transport.data.gouv.fr/datasets/reseau-de-transports-en-commun-de-la-communaute-dagglomeration-de-lauxerrois/), François Meyer chef du service mobilité

\---

\---

Les données temps réel permettent de fournir une information voyageur qui reflète la réalité du terrain. Ces données peuvent servir à la fois à la gestion de l’exploitation et à l’information des voyageurs. Cette information voyageur permet aux usagers d'optimiser leur temps de trajet. Seules les informations servant à l'informations voyageur sont publiques. Elles permettent à un usager d'être notifié si son bus a du retard, si il y a des déviations à certains arrêts pour cause de travaux etc.



Nous avons échangé avec différents producteurs de données et collectivités diffusant des données temps réel dans des formats harmonisés et supportés par le transport.data.gouv.fr afin d'avoir leurs retours d'expériences. 

Un article résumant les différents formats de données diffusés sur le PAN \[mettre lien] est également disponible sur le blog. 

**Les clients des producteurs de données temps réel** 

Les producteurs de données temps-réel peuvent avoir différents types de clients : 

* des collectivités qui veulent améliorer leur information voyageur et leur système d'exploitation comme le département de l'Isère avec Citiway, le Centre-Val-de-Loire avec Kisio ou le Grand Poitiers avec Mecatran. Ce dernier normalise leur flux temps réel custom afin d'homogénéiser les données des 40 communes
* des opérateurs de transport comme Transdev, Keolis, Eole Mobilité etc. qui sous traitent la production de leurs données à Pysae ou la SNCF qui passe par Kisio pour normaliser et avoir un contrôle qualité de leurs données 
* des stations de ski ou évènements ponctuels qui veulent avoir une information voyageur temps réel sur une courte durée voir de manière éphémère comme la [station de ski de Tignes avec Zenbus](https://transport.data.gouv.fr/datasets/horaires-theoriques-et-temps-reel-des-navettes-de-la-station-de-tignes-gtfs-gtfs-rt/)

\---

**Production et normalisation des données temps réel**

* Zenbus, Ubitransport et Pysae génèrent un flux sur le fonctionnement réel d’une exploitation de transport de voyageurs par rapport à une offre de transport théorique. Ces données servent à l'information voyageur et à la supervision des transports en commun pour les responsables d'exploitations. Elles sont produites grâce à des systèmes embarquées dans les véhicules.

![](https://assets.website-files.com/5ef534afcd35bac5a2a84fee/5ef60dc501e339c795e50c18_saeiv_schema.png "Production et diffusion des données temps réel par Pysae")

source : [article de Pysae sur le temps r](https://web.pysae.com/blog/lom-et-ouverture-des-donnees-pour-le-transport-de-voyageurs)éel

Pysae ne produit que des données GTFS-RT tandis que Zenbus et Ubitransport produisent également des données au format SIRI et SIRI Lite. Ces deux services se basent sur le fichier théorique de leurs clients quand il existe ou produisent eux même le fichier GTFS. La génération des flux sortants par le serveur Zenbus est quasi instantanée avec une actualisation des données toutes les 3 secondes pour des véhicules qui roulent avec un terminal Android muni de l'application Zenbus Driver. 

* Kisio Digital, Cityway et Mecatran ne produisent pas de données mais les normalise et les améliore à l'échelle locale comme régionale. Kisio Digital fournit, par exemple, les informations "Avance/retard" et "Perturbations" (météo, travaux, manifestation, déviation, interruption sur un tronçon etc.) ainsi que des interprétations pour proposer des itinéraires de remplacement au format GTFS-RT ou SIRI tandis que Mecatran fournit toutes les informations pouvant être contenues dans un flux GTFS-RT à leurs clients. 

\---

**Formats de données fournis** 

Les producteurs de données interrogés fournissent majoritairement, voire exclusivement pour certains, des données temps réel au format GTFS-RT à leurs clients. Ces derniers utilisant déjà le GTFS pour leurs horaires théoriques, la correspondance avec le GTFS-RT est donc plus simple. 

Les données fournies par Mecatran sont à 90% en GTFS-RT. Leurs clients préfèrent ce format car il est spécifié et les informations obligatoires sont clairement définies contrairement au SIRI qui est autoporteur mais dont les contours ne sont pas définis. Cet éditeur de logiciel peut produire du SIRI mais n'a encore eu aucune demande. 

\---

**Difficultés rencontrées lors de la production ou la normalisation des données** 

* Lorsque les données théoriques sont fournies par les clients, il peut y avoir des coordonnées géographiques qui ne sont pas valides. L'algorithme des producteurs étant sensible à la précision des données géographiques de référence, ils doivent mettre en place des outils permettant de les corriger. 

  Certains producteurs dépendent également des transporteurs, comme Pysae et Ubitransport qui doivent attendre le déclenchement des courses dans le SAEIV par les conducteurs. 
* Les services de normalisation dépendent des données que leur transmettent les opérateurs de transport : API (interface de programmation applicative), SAE, données préexistantes. La précision du flux normalisé découle de la complétude des données fournis par les transporteurs. Par exemple, certains transporteurs renseignent la couleur des lignes de transport tandis que d'autres ne le font pas. Mais encore, il peut arriver que les données temps réel et théoriques ne soient pas fournies par le même éditeur ou producteur de données. Certaines informations essentielles comme les codes d'arrêts ne sont pas normalisées pareillement, les identifiants peuvent être différents etc. Ils ne maitrisent pas la chaîne de bout en bout et doivent donc faire un fichier de mapping pour avoir une correspondance entre les arrêts et les lignes. 

La difficulté principale repose sur l'absence de standard commun dans la qualité de renseignement des données dans le système d'aide à l'exploitation (SAE). De plus, les SAE sont des outils d'exploitation qui ne sont souvent pas utilisés par des personnes qui font de l'information voyageur. Les informations doivent donc être traitées, interprétées et réadaptées.

\---

**Distribution des données temps réel**

Les données fournies par les producteurs de données normalisées appartiennent aux clients. Ils permettent à leurs clients de contrôler l’accessibilité à ces données grâce à des clés pour accéder à leur API. Cela leur permet notamment d'avoir des statistiques sur le nombre de réutilisateurs et la fréquence de réutilisation. Certains redistribuent ces données à travers des interfaces comme des écrans dans les gares, des applications mobiles etc. ou des API comme Kisio. D'autres, comme Mecatran, entrent aussi en contact avec les réutilisateurs des données de leurs clients pour leur fournir une URL lorsque les clients ne veulent pas avoir le contrôle sur toute la distribution de leurs données. Zenbus met également à disposition les données de leurs clients directement sur le PAN, ce qui permet aux réutilisateurs de récupérer le flux de différents réseaux sur une seule plateforme. La communauté de l'Auxerrois récupère les données de leur fournisseur pour les redistribuer ensuite sur le PAN. La communauté renvoie tous leurs services de mobilité comme la billettique, leur service d'information voyageur vers [transport.data.gouv.fr](transport.data.gouv.fr) pour récupérer leurs données. 

\---

**Contrôle qualité des données** 

Le contrôle qualité a surtout lieu au niveau des données théoriques. Certains producteurs, comme Kisio, installent des sondes qui leur permettent de mesurer le niveau de latence. D'autres comme Zenbus suivent le principe du “Eat your own dog food”, à savoir être les premiers utilisateurs de leurs données. Cela leur permet d'être confrontés à la qualité des données produites en étant des auditeurs permanents. 

\---

\---

Grâce à la production des données temps réel, certaines collectivités comme la Communauté de l’Auxerrois ont constaté une augmentation de l'utilisation de leur application mobile. L'ouverture de ces données permet également aux producteurs d'améliorer la qualité de leurs services. Des réutilisateurs de données de Zenbus comme Cityway ou Mybus leur font des retours d'expérience leur permettant d'adapter les informations qu'ils fournissent à leurs besoins. 

### [](https://pad.incubateur.net/KnNm3ZtDSgORWg3fw92XJg#Prochains-passages "Prochains-passages")