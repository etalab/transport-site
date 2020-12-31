---
title: "Les formats de données temps réel "
date: 2020-12-31T11:14:04.766Z
tags:
  - tutoriel
description: >-
  Cet article fait le point sur les différents formats de données supportés par
  le Point d'Accès National concernant les horaires temps réel des transports en
  commun : 

  GTFS-RT, SIRI, Siri-Lite
images:
  - /images/ùla-sdde.png
---
[transport.data.gouv.fr ](transport.data.gouv.fr)est le point d'accès national (PAN) aux données mobilité. La plateforme a pour mission de rassembler l'ensemble des données servant à l'information voyageur dans des formats harmonisés et sans obligation d'authentification pour les réutilisateurs. 

Il existe trois niveaux de fraîcheur pour les données relatives aux transports en commun ou à la demande  : 

* les horaires théoriques : horaires prévisionnels diffusés sous forme d'heure ou de fréquence de passage. 
* les horaires adaptés : modifications des horaires théoriques lorsqu'il y a des évènements modifiant les horaires et/ou itinéraires des véhicules. Par exemple, la RATP diffuse un plan de transport mise à jour en cas de grève, la SNCF livre un patch lorsqu'il y a des changements majeurs sur les horaires théoriques initialement transmis. Ces horaires ne peuvent toutefois pas être considérés comme étant en temps-réel. 
* les horaires temps réel : état du trafic à l'instant. 

Cet article traitera exclusivement des formats de données temps-réel pour les transports en commun diffusés par le PAN dans la tuile "[Temps réel transport en commun](https://transport.data.gouv.fr/datasets?type=public-transit&filter=has_realtime)". 

\---

Les données temps réel permettent de fournir une information voyageur qui reflète la réalité du terrain. Pour ce faire, il existe trois formats harmonisés et supportés par le PAN afin de modéliser cette information : 

* **Le GTFS-RT (General Transit Feed Specification - realtime)**

C'est un standard conçu par Google mais qui est désormais maintenu par une communauté open data. 

Ce format utilise une méthode globale permettant de récupérer toutes les données d'un réseau en une requête. 

 Ce flux temps réel peut contenir trois types d'information : 

* `TripUpdate` qui correspond à la mise à jour des horaires de passage
* `Alert`  qui génère des alertes de service
* `VehiclePositions` qui renseigne la position des véhicules

Certains producteurs proposent toutes ces informations dans un seul flux, comme [Zenbus](https://transport.data.gouv.fr/datasets?_utf8=%E2%9C%93&q=zenbus), tandis que d'autres préfèrent avoir un flux par type d'information. C'est le cas pour la [Communauté de l’Auxerrois](https://transport.data.gouv.fr/datasets/reseau-de-transports-en-commun-de-la-communaute-dagglomeration-de-lauxerrois/) qui a publié un flux pour `TripUpdate`et un autre pour `VehiclePositions`

![](/images/capturemls.png)

Le GTFS-RT doit être accompagné d'un fichier théorique au [format GTFS](https://gtfs.org/reference/static) pour pouvoir être utilisé. Ces données ne sont pas donc pas autoporteuses.\
Par exemple, pour les données de mise à jour des horaires (`TripUpdate`), pour un `Trip` donné on a la mise à jour de ses horaires pour la journée, mais pas d'informations concernant la `Route` de ce `Trip` ni la position des arrêts. Ces informations sont fournis dans le GTFS. 

\---

* **Le SIRI (Service Interface for Realtime Information)**

Le SIRI est une norme définie par le Comité Européen de Normalisation et correspond à la norme [Netex](http://netex-cen.eu/) pour le temps réel. Elle caractérise des services temps réel dont les principaux sont : 

* `Stop Monitoring` qui affiche les prochains passages
* `Estimated Timetable` qui met à jour des horaires de passage)
* `General Message` qui génère des alertes de service
* `Vehicle Monitoring` qui renseigne la position des véhicules

Tout comme le Netex, un profil doit être défini. C'est un format autoporteur mais les données ne sont pas interopérables entre les profils car les services définis sont sélectionnées avec les profils.

\---



* **Le SIRI Lite**

Le SIRI Lite est un sous dérivé de SIRI qui ne contient que les informations suivantes afin de le rendre plus accessible : 

* `StopMonitoring` qui affiche les prochains passages
* `StopPointsDiscovery` / `LineDiscovery` qui fournit des informations sur le réseau
* `GeneralMessage`  qui génère des alertes de service



\---

\---



La production et diffusion des données temps réel en SIRI, GTFS-RT et Siri Lite sur des portails à accès libre permettent aux Autorités Organisatrices de la Mobilité (AOM), à savoir l'autorité en charge de l’organisation du réseau de transport [](https://fr.wikipedia.org/wiki/Transports_urbains "Transports urbains")sur son territoire, d'être conforme à la réglementation. En effet, [la Loi d'Orientation des Mobilités](https://www.legifrance.gouv.fr/loda/id/JORFTEXT000039666574/2020-12-30/) (LOM) promulguée le 24 décembre 2019  a fixé un cadre législatif pour l’ouverture des données temps servant à l'information voyageur. L'ouverture de données étant attendu au 1er décembre 2020.