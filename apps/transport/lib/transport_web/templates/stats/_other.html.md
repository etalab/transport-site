## Transport collectif, temps réel

Une réunion de lancement des travaux a eu lieu le 20 septembre 2018. Le compte-rendu est disponible [ici](<%= @cr_tr %>).

## Lieux de covoiturage

[Un fichier national](https://www.data.gouv.fr/fr/datasets/aires-de-covoiturage-en-france) décrivant les lieux de covoiturage de 70 départements a été consolidé par BlaBlaCar.

La Fabrique des Mobilités a récemment ouvert un fichier relatif à des lieux de rendez-vous de covoiturage (grande variété de points, fichier non consolidé), disponible sur [ici](https://www.data.gouv.fr/fr/datasets/base-de-donnees-commune-des-lieux-et-aires-de-covoiturage/).

## Infrastructures de recharge pour véhicules électriques (IRVE)

Depuis septembre 2018, les données sont consolidées de manière automatique par Etalab. Le fichier est disponible [ici](https://www.data.gouv.fr/fr/datasets/fichier-consolide-des-bornes-de-recharge-pour-vehicules-electriques/). Le code source est disponible [ici](https://github.com/etalab/schema.data.gouv.fr/blob/master/irve/aggregration/irve.ipynb).

Les fichiers sources doivent être au format csv et respecter le format défini par [l’arrêté du 12 janvier 2017](https://www.legifrance.gouv.fr/affichTexte.do?cidTexte=JORFTEXT000033860733&categorieLien=id) pour apparaitre dans la version consolidée, notamment sur les colonnes id_pdc et date_maj qui servent de pivot. Plus d'informations sur le format attendu sont disponibles [ici](https://www.data.gouv.fr/fr/datasets/fichier-exemple-stations-de-recharge-de-vehicules-electriques/).

## Vélos en libre service

Une réunion de lancement a eu lieu le 16 octobre 2018. Le compte-rendu est disponible [ici](<%= @cr_vls %>).

## Données routières

Elles seront abordées courant 2019.
