---
title: Gtfs2NetexFr, un outil open source intégré au Point d'Accès National !
date: 2020-06-25T15:49:10.984Z
tags:
  - qualité des données
description: Retrouvez désormais pour l'ensemble des fichiers GTFS référencés
  sur transport.data.gouv.fr le fichier NeTEx (profil France) associé.
image: /images/gtfs2netexfr.png
---
La plateforme transport.data.gouv.fr doit correspondre aux exigences attendues d’un point d’accès national aux données transports, tel que défini par le règlement européen. Une des missions prévues des Point d’Accès Nationaux est l’harmonisation des données de transport sur le territoire - en vue de permettre une meilleure interopérabilité au niveau européen. 

Lors de la réunion de lancement de transport.data.gouv.fr en Juillet 2017, plusieurs producteurs de données ont partagé leurs difficultés à produire des données aux formats standards comme le NeTEx. En revanche, elles peuvent mettre à disposition des données dont elles disposent, dans des formats autres. 

> Pour rappel, le NeTEx est le standard européen qui a été développé pour les données transports afin d'en garantir l'interopérabilité. Des profils adaptés par pays sont également définis. Les opérateurs de transport et les autorités organisatrices de mobilité sont tenues de mettre à disposition des données suivant la norme NeTEx. 
>
> Le GTFS est le standard le plus utilisé par les services de mobilité d’information voyageur multimodale. Il est moins riche, mais plus répandu que le NeTEx et plus simple à utiliser (plus d’outils compatibles et plus simple de développer ses propres outils).

L’équipe transport.data.gouv.fr fait alors le choix d’accepter de référencer les données d’horaires théoriques pour les transports en commun dans 2 formats : au format GTFS et au format NeTEx. Le premier car il est un standard largement développé dans l'industrie à la fois du côté des réutilisateurs que du côté des producteurs ; obliger certains producteurs à produire des fichiers NeTEx supposait des opérations coûteuses. Le second car il est le seul garant de l'interopérabilité des données à l'échelle européenne.

Laisser le choix du format imposait que le Point d'Accès National, et permettre la publication de GTFS, a imposé la nécessité d'un convertisseur qui puisse générer les fichier NeTEx conformément au règlement européen. Ce convertisseur pourra soulager les producteurs de données tout en garantissant la standardisation des données. Son coûtest mutualisé au niveau national et est disponible en open source. 

et propose de développer à terme un convertisseur GTFS vers NeTEx. 



La volonté de l’équipe est de soulager les producteurs de données du coût supplémentaire induit par la normalisation des données. 
Si on demande aux producteurs uniquement d’ouvrir des données au format NETEX, on n'aura aucunes données. 
Un convertisseur mutualisé au niveau national, en open source. 

Concrètement, qu’est ce que cela veut dire pour les producteurs de données : 
Vous publiez des données au format GTFS
S’il n’y a pas d’erreurs, paf ! c’est magiquement converti au format NETEX.
Vous pouvez retrouver le fichier au format NETEX ici sur la plateforme. Il suffit de cliquer sur l'hyperlien pour le télécharger : (screenshot)
Ceci veut dire que les collectivités/producteurs de données seront bien en règle vis à vis de leurs obligations d’ouverture des données et mise en conformité s’ils publient juste des données au format GTFS - car la conversion vers le NETEX est prise en compte. 

L’outil convertisseur est disponible en open source ici : 
Si vous souhaitez en savoir plus, vous pouvez consulter l’excellent article qu’y a consacré Bertrand Billoud (Kisio Digital) ici : 
http://lafabriquedesmobilites.fr/articles/innovation/gtfs2netexfr-nouvel-outil-open-source-pour-faciliter-la-production-de-donnees-transport-au-format-netex/