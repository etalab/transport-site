---
title: "Paroles de réutilisateur : Affluences"
date: 2024-12-11T08:31:47.703Z
tags:
  - réutilisation
description: Affluences présente sa solution de comptage en temps réel dans les
  transports en commun
images:
  - /images/affluences.png
---
**Interview avec Martin BOURREAU, Technical Product manager chez [AFFLUENCES](https://www.pro.affluences.com/)**

Affluences est une start-up française spécialisée dans la mesure et la communication de l’affluence en temps réel. Sa vocation est d’aider les usagers à mieux se répartir dans le temps et dans l’espace, et d’aider les collectivités et opérateurs à faire correspondre l’offre et la demande.

Affluences est réutilisateur des données du PAN. Nous leur avons posé quelques questions pour mieux comprendre comment ils réutilisent ces données.

**Transport.data.gouv.fr : Pouvez-vous nous parler d’Affluences et votre spécificité pour le comptage dans les transports ?**

Nous sommes une entreprise multisectorielle, qui aide des établissements prestigieux à connaître et maîtriser leurs flux (Musée du Louvre, Mont-Saint-Michel, Château de Versailles, etc). Pour tous ces clients, nous avons déployé une architecture technique “SaaS” : les compteurs renvoient en temps réel les données de comptage directement à nos serveurs distants, dans le cloud.

Lorsque nous sommes arrivés dans le secteur des transports, en 2021, nous avons été surpris de voir que beaucoup de données sont encore présentes physiquement / en local, avec un déchargement des données au dépôt une fois par jour… Donc on peut dire que notre architecture technique, qui consiste à minimiser le matériel à bord, représente une spécificité.

Enfin, la communication de l’affluence au public - aux voyageurs dans notre cas - fait partie de notre ADN.

**Transport.data.gouv.fr : Pourquoi le système Cloud vous parait-il plus adapté que le serveur local dans les transports en commun ?**

Le cloud permet une mise à disposition de l’information partout et tout le temps : la résilience des serveurs cloud est bien meilleure que celle des serveurs “en local”, c’est d’ailleurs la raison pour laquelle le cloud tend à se démocratiser dans tous les secteurs d’activité.

Cette architecture technique nous aide aussi à accéder plus facilement aux compteurs à distance, et à être avertis instantanément en cas de dysfonctionnement. Et puis cela permet de minimiser le matériel chez le client et de mettre à jour nos algorithmes en permanence.

Le Cloud, c’est l’architecture technique des prochaines années - alors que les calculateurs en local c’est l’architecture technique des années passées.

**Transport.data.gouv.fr : et l’open data dans tout ça ?**

Ah oui ! Dans les transports, les données métier sont primordiales parce qu’il faut rattacher les données sur l’affluence au moyen de transport.  L’open data joue un rôle central dans cette architecture technique, parce qu’elle permet 3 choses : 

* d’accéder instantanément aux données (un seul chemin, le PAN) sans avoir besoin de demander des autorisations parfois longues à obtenir ;
* d’accéder aux données dans un format standard - donc d’éviter d’avoir à développer des interfaçages “sur-mesure” pour chacun de nos clients et de favoriser l’interopérabilité ;
* de bénéficier du contrôle qualité de la plateforme, ce qui assure la qualité des données en amont et fluidifie le temps de déploiement.

D’une certaine manière, l'open data favorise la concurrence et lève les barrières à l’entrée parce qu’elle réduit les intermédiaires et permet de baisser les coûts d’interfaçage.

![](/images/affluences.png "Avantages des compteurs 3D Affluences")

**Transport.data.gouv.fr : du coup, comment utilisez-vous les données du PAN ?**

Nous utilisons les données en open data à la place des connecteurs “physiques” avec le SAE, dans les bus, les tramways ou les trains. Nous utilisons presque tous les flux à notre disposition : 

* Le plan de transports théorique (GTFS ou NeTEx) pour intégrer les informations sur les arrêts et les courses prévues ;
* Le plan de transports en temps réel (GTFS-RT ou SIRI) pour intégrer savoir quel véhicule dessert quelle course à quel moment, et mettre à jour les données théoriques.

Cela nous permet de contextualiser les données sur l’affluence, de les rendre compréhensibles et surtout interprétables.

**Transport.data.gouv.fr : par rapport à ces données, qu’est-ce qui vous semble améliorable ?**

Nous pensons à deux axes d’améliorations :

* Continuer à travailler avec les producteurs de données pour avoir des données toujours plus exhaustives, toujours plus précises, fraîches et qualitatives ;
* Contribuer à l’intégration de l’information sur l’affluence, presque jamais disponible dans ces flux de données en open data.Pourtant les logiciels MaaS pourraient l’intégrer aux moteurs d’itinéraire, cela pourrait même un critère de choix de l’itinéraire.

Si des réseaux souhaitent valoriser leur open data par le prisme de l’affluence, nous sommes ouverts à de nouvelles collaborations !