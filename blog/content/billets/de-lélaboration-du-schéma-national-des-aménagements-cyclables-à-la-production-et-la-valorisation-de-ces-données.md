---
title: "De l'élaboration du schéma national des aménagements cyclables à la
  production et la valorisation de ces données "
date: 2021-12-08T08:12:29.375Z
tags:
  - retour d'expérience
description: Cet article relate le travail collaboratif qui a été mené avec Vélo
  & Territoires et Géovélo pour élaborer le schéma national des aménagements
  cyclables ainsi que leur implication pour faciliter la production et leur
  valorisation de ces données
images:
  - /images/vttdgv.png
---
<!--StartFragment-->

Le [schéma national des aménagements cyclables](https://schema.data.gouv.fr/etalab/schema-amenagements-cyclables/) permet d’harmoniser la production des données sur les aménagements cyclables tels que pistes cyclables, voies vertes, vélorues etc. L’usage d’un standard partagé et l’ouverture de ces données a notamment pour objectif de permettre aux services d’informations voyageurs d’intégrer ces données plus simplement, à moindre coût, et de faciliter les échanges de données entre les collectivités. Cela permet également aux collectivités de répondre à leurs obligations d’ouverture des données fixées par [Règlement délégué (UE) 2017/1926](https://eur-lex.europa.eu/legal-content/FR/TXT/PDF/?uri=CELEX:32017R1926&from=IT) concernant la mise à disposition de services d’informations sur les déplacements multimodaux.

<!--EndFragment-->

<!--StartFragment-->

L’élaboration de ce schéma a été un travail collaboratif mené avec un groupe de travail composé de collectivités, réutilisateurs et associations vélos. Vous trouverez la liste des participants dans la [documentation](https://doc.transport.data.gouv.fr/producteurs/amenagements-cyclables/contribution-au-schema-sur-les-amenagements-cyclables) du schéma.

Deux organisations nous ont accompagné tout au long de l’opération, de l’élaboration du schéma à la production et la réutilisation des données sur les aménagements cyclables :

·   [Vélo & Territoires](https://www.velo-territoires.org/), un réseau de collectivités qui rassemble plus de 140 territoires adhérents, mobilisés dans une dynamique collégiale pour construire la France à vélo en 2030. Thomas Montagne et Fabien Commeaux ont co-animé tous les ateliers avec l’équipe de [Transport.data.gouv.fr](https://transport.data.gouv.fr/) et ont apporté leur connaissance métier. L’association anime notamment l'[Observatoire national des Véloroutes](https://www.velo-territoires.org/observatoires/observatoire-national-des-veloroutes-et-voies-vertes/#), un système d’information géographique qui permet de mesurer l’état d’avancement des différents réseaux cyclables, et la [Plateforme nationale des fréquentations](https://www.velo-territoires.org/observatoires/plateforme-nationale-de-frequentation/) qui permet de mutualiser, d’agréger et de diffuser des données de comptage vélo au niveau national

·   [Geovelo](https://geovelo.fr/a-propos/), qui développe une application gratuite de calcul d'itinéraires vélo pour laquelle l'entreprise produit et réutilise des données sur les thématiques vélo. Cette organisation contribue depuis plusieurs années à l’enrichissement des données sur les aménagements cyclables sur OpenStreetMap (OSM). En complément des travaux effectués par la communauté OSM, les équipes de Geovelo complètent régulièrement les données sur la base de deux sources principales :

* les signalements que peuvent envoyer leurs utilisateurs à travers l’application ou le site Geovelo, pour informer d’aménagements cyclables ou de parkings vélo qui ne seraient pas encore référencés dans OSM,
* les données que leur fournissent les collectivités partenaires, qui les missionnent pour s’assurer que la base OSM reflète bien l’intégralité des aménagements cyclables présents sur leur territoire.

La participation de l’équipe de Geovelo aux ateliers nous a permis de mieux comprendre les besoins des réutilisateurs des données vélo et nous a aidé à  articuler le schéma national avec OSM. <!--StartFragment-->

<br />

<!--EndFragment-->

### 1. L’état des lieux des données existantes et l’identification des besoins et compétences des collectivités



Nous avons repris les travaux sur les données des aménagements cyclables en décembre 2019 car nous avions une forte demande de la part des collectivités et des réutilisateurs. 

Ces travaux ont débuté par une [enquête réalisée par Vélo & Territoires](https://www.velo-territoires.org/politiques-cyclables/data-velo-modeles-donnees/schema-donnees-amenagements-cyclables/) auprès de 70 collectivités pour savoir si elles disposaient de données sur les aménagements cyclables et ressentaient le besoin d’avoir un modèle de données. La moitié des collectivités ont confié leurs difficultés à décrire leurs aménagements d’un point de vue sémantique et à les numériser dans un système d’information géographique (SIG). Pour 80 % des territoires enquêtés, un standard national serait utile et faciliterait leur travail. Cette enquête a également permis d’évaluer les besoins de potentiels utilisateurs pour développer des outils d’aide à la numérisation.  

En parallèle, l’équipe de [Transport.data.gouv.fr](https://transport.data.gouv.fr/) faisait un état des lieux des données existantes en se basant notamment sur le [modèle d’Île-de-France Mobilités](https://data.iledefrance-mobilites.fr/explore/dataset/amenagements-velo-en-ile-de-france/information/), co-conçu par Geovelo, et les [attributs d’Open Street Map](https://wiki.openstreetmap.org/wiki/FR:Bicycle) (OSM). Le modèle d’Île-de-France Mobilités  avait été réutilisé et validé par plusieurs autres collectivités, partenaires de Geovelo. La compatibilité du schéma national avec la base OSM était importante car cette dernière est réactive aux évolutions fréquentes des réseaux cyclables, mais aussi car elle est privilégiée par la majorité des applications GPS spécifiques au vélo. <!--StartFragment-->

<br />

<!--EndFragment-->

### 2. L’élaboration du schéma national des aménagements cyclables



À l'issue de ces deux investigations, cinq ateliers ont été animés. La plus grande difficulté a été de réduire le nombre de champs pour n’avoir que des champs tournés vers l’utilité aux usagers finaux car les collectivités voulaient ajouter des champs qui répondaient seulement à des besoins métiers comme le type de signalisation sur la voie, le nom du gestionnaire de l’aménagement, la dernière date de travaux etc. Cette difficulté a été levée en réexpliquant aux collectivités l’utilité de ces données et grâce aux interventions de Geovelo qui ont recentré les échanges sur l’information voyageur. 

Le schéma a été publié sur [schema.data.gouv.fr](https://schema.data.gouv.fr/) le 10.12.2020 et de premières données ont été publiées en avril 2021. Ces données sont issues d’OSM et ont été mises en conformité avec le schéma national par Geovelo pour [Tours Métropole](https://transport.data.gouv.fr/datasets/pistes-cyclables-tours-metropole-val-de-loire/). <!--StartFragment-->

<br />

<!--EndFragment-->

### 3. Le développement d'outils pour faciliter la production des données et accélérer leur ouverture



Afin de faciliter la transition vers le schéma national, et pouvoir en suivre les évolutions, Geovelo a développé un outil d’extraction qui permet aux collectivités partenaires de récupérer quand elles le souhaitent, au format du schéma national, [la base existante dans OSM](https://www.amenagements-cyclables.fr/fr/facilities).

![](/images/capture-d’écran-2021-09-10-105144-1-.png)

\
[Tutoriel pour extraire les données à partir de l'espace adhérent Géovélo. ](https://www.linkedin.com/posts/transportdatagouvfr_geovelo-a-int%C3%A9gr%C3%A9-le-sch%C3%A9ma-national-des-activity-6844517734546452480-5Yg1)

\
En plus de l’outil d’extraction que met à disposition Géovélo à toutes les collectivités partenaires dans le tableau de bord que Geovelo leur configure, il y a la possibilité de paramétrer des exports personnalisés comme l’ajout de champs facultatifs ou des “zones 30”. L’intérêt est de profiter de la profondeur de la base OSM, pour alimenter les données métier des collectivités.\
Géovélo publie également la [base nationale des aménagements cyclables ](https://transport.data.gouv.fr/datasets/amenagements-cyclables-france-metropolitaine/)publiée sur [Transport.data.gouv.fr](https://transport.data.gouv.fr/) et basée sur un export des données publiées sur OSM. Ce jeu de données est mise à jour tous les mois. \
Simon Réau, de Geovelo, participe également activement à l’évolution du schéma national en votant en tant que réutilisateur dès qu’il y a une [demande de modification du schéma en cours](https://doc.transport.data.gouv.fr/producteurs/amenagements-cyclables/contribution-au-schema-sur-les-amenagements-cyclables).

L’équipe de Vélo & Territoires a développé plusieurs outils d’aide à la numérisation en tenant compte des réalités très différentes qu’il peut y avoir d’un territoire à l’autre en termes de moyens techniques et humains. En effet, entre une petite commune rurale et une métropole, la question de la production de données ne peut être abordée de la même manière.

Fabien Commeaux et Thomas Montagne ont donc développé des outils qui puissent répondre aux besoins de chacun : 

* une petite commune peut se connecter sur le [WebSIG](https://on3v.veremes.net/vmap/?mode_id=vmap&map_id=31&token=publictoken) depuis un simple navigateur internet et saisir graphiquement ses quelques aménagements cyclables
* une commune plus importante, qui dispose de compétences en géomatique, fera plutôt le choix d’utiliser [des gabarits de table SIG ou de base de données](https://on3v.veremes.net/vmap/?mode_id=vmap&map_id=31&token=publictoken) 

En complément de ces outils, Vélo & Territoires a rédigé un [guide de numérisation](https://www.velo-territoires.org/wp-content/uploads/2021/03/AC_NOTICE_NUMERISATION_0.3.0.pdf) qui vise à donner quelques repères et bonnes pratiques, quel que soit l’outil utilisé pour produire les données.\
Nous avons également produit une [documentation spécifique sur les aménagements cyclables](https://doc.transport.data.gouv.fr/producteurs/amenagements-cyclables/guide-de-numerisation) avec leur équipe. Cette documentation répond à un des besoins identifiés lors des enquêtes de 2019, à savoir s’accorder sur une sémantique commune. <!--StartFragment-->

<br />

<!--EndFragment-->

### 4. La valorisation de ces données par la réutilisation



Vélo & Territoires est également réutilisateur des données sur les aménagements cyclables. Leur équipe retraite l’ensemble de ces données pour produire une couche nationale unique et sans doublon, qui agrège la donnée publiée par les collectivités et celle d’OSM partout ailleurs, grâce au travail de Geovelo. Cette couche est mise à jour au fil de l’eau, dès qu'il y a des mises à jour, et est présentée sur le [WebSIG](https://on3v.veremes.net/vmap/?mode_id=vmap&map_id=31&token=publictoken) et téléchargeable par tous. 

![Carte WebSIG Vélo & Territoires du 8.12.2021](/images/carte-websig.png "Carte WebSIG Vélo & Territoires du 8.12.2021")

[Tutoriel pour accéder à la carte des aménagements cyclables à partir du WebSIG de Vélo & Territoire*s*](https://www.linkedin.com/posts/transportdatagouvfr_carte-sur-les-am%C3%A9nagements-cyclables-activity-6840528657333661697-RHdU).

<!--StartFragment-->

<br />

<!--EndFragment-->

<!--StartFragment-->

<br />

<!--EndFragment-->

<br />

Ces deux organisations appuient l’équipe de [Transport.data.gouv.fr](https://transport.data.gouv.fr/) dans l’accompagnement aux collectivités pour l’ouverture de leurs données sur les aménagements cyclables.\
Vélo & Territoires accompagne leurs adhérents pour les aider dans le déploiement du modèle, les mettre en contact quand ils rencontrent les mêmes problématiques et peut également animer des temps d’échanges spécifiques en fonction des besoins. 

<!--StartFragment-->

<br />

<!--EndFragment-->

<br />

Un grand merci à l’équipe de Vélo & Territoires et celle de Geovelo pour leur accompagnement qui nous facilite l’ouverture des données vélo.

Retrouvez-les dans notre section dédiée aux organisations qui facilitent l’ouverture des données sur [Transport.data.gouv.fr](https://transport.data.gouv.fr/) ici : <https://doc.transport.data.gouv.fr/notre-ecosysteme/les-facilitateurs>

<!--StartFragment-->

<br />

<!--EndFragment-->

<!--StartFragment-->

<br />

<!--EndFragment-->

<br />

Article co-rédigé avec :\
Geovelo : Antoine Laporte Weywada et Simon Réau\
Vélo & Territoires : Fabien Commeaux et Thomas Montagne\
[Transport.data.gouv.f](https://transport.data.gouv.fr/)r : Miryad Ali

<!--EndFragment-->