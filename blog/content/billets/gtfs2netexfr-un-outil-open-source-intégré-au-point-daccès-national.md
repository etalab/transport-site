---
title: Gtfs2NetexFr, un outil open source intégré au Point d'Accès National !
date: 2020-06-25T15:49:10.984Z
tags:
  - qualité des données
description: Retrouvez désormais pour l'ensemble des fichiers GTFS référencés
  sur transport.data.gouv.fr le fichier NeTEx (profil France) associé.
image: /images/gtfs2netexfr.png
---
### **Pourquoi un convertisseur ?**

La plateforme transport.data.gouv.fr doit correspondre aux exigences attendues d’un point d’accès national aux données transports, telles que définies par le règlement européen. Une des missions prévues des Point d’Accès Nationaux est **l’harmonisation des données de transports** sur le territoire - en vue de permettre une meilleure **interopérabilité** au niveau européen. 

Lors de la réunion de lancement de transport.data.gouv.fr en Juillet 2017, plusieurs producteurs de données ont partagé leurs **difficultés à produire des données aux formats standards comme le NeTEx**. D'autres formats comme le GTFS étaient utilisés et pouvaient déjà être ouverts.

> Pour rappel, le [format NeTEx](http://netex-cen.eu/) est le standard européen qui a été développé pour les données transports afin d'en garantir l'interopérabilité. Des profils adaptés par pays sont également définis. Les opérateurs de transports et les autorités organisatrices de mobilité sont tenues de mettre à disposition des données suivant la norme NeTEx. 
>
> Le [GTFS](https://developers.google.com/transit/gtfs?hl=fr) est le standard le plus utilisé par les services de mobilité d’information voyageur multimodale. Il est moins riche, mais plus répandu que le NeTEx et plus simple à utiliser (plus d’outils compatibles et plus simple de développer ses propres outils).

L’équipe transport.data.gouv.fr fait alors le choix d’accepter de référencer les données d’horaires théoriques pour les transports en commun dans 2 formats : au format GTFS et au format NeTEx. Le premier car il est un standard largement développé dans l'industrie à la fois du côté des réutilisateurs que du côté des producteurs ; obliger certains producteurs à produire des fichiers NeTEx supposait des opérations coûteuses. Le second car il est le seul garant de l'interopérabilité des données à l'échelle européenne.

**Laisser le choix** du format et permettre la publication de GTFS a imposé la **nécessité d'un convertisseur** qui puisse générer les fichier NeTEx conformément au règlement européen. Le Ministère des Transports a confié à [Kisio Digital](https://wiki.lafabriquedesmobilites.fr/wiki/Kisio) la mission de développer l'outil de conversion des données GTFS en données NeTEX profil France.

### **A quoi sert-il aujourd'hui ?**

L’outil est désormais disponible en open source ici : <https://github.com/CanalTP/transit_model/tree/master/gtfs2netexfr>


> Si vous souhaitez en savoir plus sur son fonctionnement, vous pouvez consulter l’excellent article qu’y a consacré Bertrand Billoud (Kisio Digital) ici : 
> <http://lafabriquedesmobilites.fr/articles/innovation/gtfs2netexfr-nouvel-outil-open-source-pour-faciliter-la-production-de-donnees-transport-au-format-netex/>

Cet outil est déjà utilisé par la plateforme transport.data.gouv.fr pour **produire**, **pour chaque fichier GTFS** référencé, **son équivalent NeTEx**. Ce fichier NeTEx peut être retrouvé dans les **ressources communautaires** de chaque dataset (sur transport.data.gouv.fr comme sur data.gouv.fr).

![](/images/capture-d’écran-2020-06-26-à-19.45.10.png "Résultat de la conversion du dernier GTFS publié pour le réseau TC de Lyon.")

Concrètement, cela permet à l'ensemble des producteurs de données qui fournissent un fichier GTFS de **respecter le règlement européen** et participer à la **constitution d'un référentiel européen harmonisé**. L'opération permet également de **mutualiser le coût** qu'aurait supposé la production par chaque producteur d'un fichier NeTEx adapté.