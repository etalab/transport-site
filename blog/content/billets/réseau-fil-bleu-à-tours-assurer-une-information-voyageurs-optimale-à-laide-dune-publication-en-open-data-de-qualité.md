---
title: "Réseau Fil Bleu à Tours : assurer une information voyageurs optimale à
  l'aide d'une publication en open data de qualité"
date: 2023-04-11T07:59:47.853Z
tags:
  - qualité des données
description: " Nicolas Béhier-Dévigne, Gestionnaire d’applications pour Keolis
  Tours, réseau Fil Bleu, répond aux questions de transport.data.gouv.fr et
  détaille la démarche de publication en open data des données de leur réseau
  urbain."
images: []
---
**Bonjour Nicolas Béhier-Dévigne, pourriez-vous vous présenter ?**\
Je travaille chez Keolis Tours depuis 10 ans dans la Direction Innovation, Projets et Systèmes d’Information. J’assure des missions de conduite de projets orientés voyageurs (Mise en place du site web, de l’application mobile, de la e-boutique, de la chaîne de saisie et diffusion de la perturbation, etc.) et du développement des traitements de données (Développements Talend ETL/ESB principalement).

**Pourriez-vous nous en dire plus sur le réseau Fil Bleu de Tours ?**\
Le Syndicat des Mobilités de Touraine délègue la gestion du réseau Fil Bleu à Keolis Tours. Il regroupe 25 communes autour de Tours Métropole Val de Loire. Il est composé d’une ligne de tram, une BHNS, 26 lignes de bus, 11 lignes de transport à la demande, 8 lignes spéciales, 7 parkings relais et 15 parcs à vélos.

**Comment utilisez-vous le PAN, transport.data.gouv.fr, pour répondre à vos besoins et obligations ?**\
Nous publions nos données au format GTFS et GTFS-RT sur l’open data de notre métropole. Le PAN moissonne ces données à partir de ce point d’accès.

Nous avons fait le choix chez Fil Bleu en 2022 de créer une base de données qui centralise l’ensemble de nos données théoriques et temps réel, en particulier celles en provenance de nos systèmes industriels. De cette manière, nous pouvons croiser et consolider nos différents référentiels, et maîtrisons la construction et diffusion de nos données. Cela nous permettra par exemple d’ici quelques semaines d’assembler la donnée en provenance de plusieurs Systèmes d’Aide à l’Exploitation pour ne diffuser qu’un GTFS-RT, regroupant tous nos modes de transport.

Nous avons développé une interface pour générer et publier notre GTFS. Celle-ci nous permet de paramétrer notre export (pour inclure ou non certains fichiers d’extensions, tout ou partie de nos lignes, etc.) et de définir si l’archive est simplement déposée sur un dossier partagé, un FTP particulier, ou via API pour le publier automatiquement sur l’open data.

Nous avons aussi ajouté récemment une étape d’audit via [le validateur GTFS du PAN](https://github.com/etalab/transport-validator) (en utilisant l’API de ce service). Si l’audit révèle des erreurs dans notre archive, la publication est stoppée, et le rapport d’audit est envoyé par e-mail à notre équipe Métiers.

![Outil d'export et de publication de données au format GTFS développé par Keolis Tours. L'interface propose de choisir des paramètres d'exports : lignes, tracés etc](/images/keolis-tours-publication-gtfs.png "Outil d'export et de publication de données au format GTFS développé par Keolis Tours")

**Pourriez-vous nous expliquer l'importance de l'information voyageurs ?**\
Notre équipe Informations Voyageurs travaille conjointement avec l’équipe Produits qui définit le périmètre de l’offre, et les Méthodes Exploitation qui la saisissent dans les outils. Ils s’assurent que les voyageurs retrouvent toujours les mêmes horaires peu importe le média : Calculateur d’itinéraire, dépliant horaire, grille horaire sur le site web ou affichées sur le terrain. Il est donc primordial que l’ensemble de ces productions se base sur les mêmes données.

Et il faut aussi s’assurer que l’ensemble des autres outils (signalement voyageurs, main courante, gestion du mobilier, diffusion du temps réel, cartographie dynamique, reporting, tableaux de bords, etc.) s'appuie sur des référentiels à jour pour garder de la cohérence.

**Comment assurez-vous la qualité de celle-ci ? Avez-vous toujours suivi ce processus pour vous assurer de la qualité de vos données ?**\
Nous utilisions auparavant l’export GTFS fourni par notre agrégateur de données de la région Centre-Val de Loire. Nous n’avions donc pas la main sur l’ensemble des données diffusées. En concentrant et traitant nous-mêmes l’ensemble de nos sources, puis en développant les exports aux formats souhaités cela nous permet de maîtriser l’ensemble de la chaîne d’information.

En passant par une étape de validation automatique par le validateur GTFS du PAN, nous nous assurons de diffuser nos données si seulement si elles sont techniquement valides.

Pour s’assurer que notre offre est correctement représentée dans le GTFS, les données graphiquées et concentrées dans notre référentiel sont exportées dans un format GTFS étendu. L'équipe Produits les valide d’abord sous la vision dépliant horaire, puis l’équipe Information Voyageurs les contrôle dans le calculateur d’itinéraire et la cartographie dynamique de pré-production. Si ce jeu de données “figées” est validé, il devient la source des différents exports (Mise à jour du calculateur d’itinéraire, des référentiels du site internet, export du GTFS pour l’open data, export du GTFS pour l’outil de production des grilles horaires et dépliants horaires, etc.).

**Quelque chose à ajouter ?**\
Les échanges avec le transport.data.gouv.fr sont de qualité et ils nous accompagnent bien dans l’ouverture de nos données. Cet accompagnement facilite le partage de nos données ouvertes, accessibles et de qualité, pour permettre à d’autres acteurs de proposer d’autres services et usages.