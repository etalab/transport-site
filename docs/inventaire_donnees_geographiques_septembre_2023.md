# Les jeux de données

Les jeux de données n’ont pas d’information géographique en propre (pas de coordonnées, de polygone, etc), mais en ont à travers leur couverture géographique, leurs responsables légaux, et évidemment le contenu des ressources.

## La couverture géographique

**Les datasets ont une couverture géographique, qui apparaît sur la carte de la page d’un dataset.** C’est une information indicative qui est indépendante de la réalité de ce qui est contenu dans les resources, qui peut allégrement dépasser cette couverture ou être bien plus réduit. **Cette couverture géographique est soit :**

1. une région (champ `region_id`)
    - Une vraie région
    - Une région spéciale : la France entière
2. un AOM – (champ `aom_id`)
3. une ou plusieurs communes (à travers la table de jointure `datasets_communes`). Dans le dernier cas, ils ont (dans les faits) toujours le champ `associated_territory` qui est rempli, et qui donne un nom à l’ensemble des communes (exemple : “Métropole du Grand Lyon”). Ce champ est exclusif des deux autres, mais c’est une pratique qui n’est pas obligatoire dans le code.

Dans les deux premiers cas, la région ou l’AOM sont renseignés à la main à travers le backoffice.

Par contre la couverture communale est aspirée depuis data.gouv, lorsque la couverture d’un JDD inclut soit des communes, soit des EPCI, voir `apps/transport/lib/transport/import_data.ex#read_datagouv_zone`,  puis le champ `associated_territory` est renseigné à la main à travers le backoffice.

**La couverture territoriale du dataset est simplement considérée comme la géométrie (polygone) de la région, de l’AOM, ou de l’ensemble des communes.**

Il y a des limites à ce mécanisme de couverture géographique : par exemple il y a des jeux de données départementaux qui sont indiqués comme ayant une couverture régionale (donc la carte est incorrecte, et *plus grave, ça perturbe aussi la recherche par commune puisque en cherchant une commune, un dataset d’un autre département de la même région peut remonter*) : [https://transport.data.gouv.fr/datasets/reseau-interurbain-cars-region-cantal-15](https://transport.data.gouv.fr/datasets/reseau-interurbain-cars-region-cantal-15) (remarque : dans ce cas, aucune couverture géographique n’est indiqué sur data.gouv…). De même, plutôt que relier à l’objet EPCI (intercommunalité, communauté de communes, métropole…), on préfère indiquer une collection de communes, sans dire «mais en réalité il s’agit de tel EPCI qui a un nom »..

D’après Cyril, il est possible d’avoir des jeux de données avec des couvertures territoriales baroques, qui ne recouvrent pas une collectivité territoriale mais par exemple, soit pour 2 EPCI, ou seulement une partie d’un EPCI… À prendre en compte lors de la refonte de ce mécanisme.

## Le représentant légal

**Un dataset peut être rattaché à un ou plusieurs régions et/ou un ou plusieurs AOM en tant que «représentant légal».** Cela est réalisé à travers deux tables de jointures, dataset_region_local_owner et dataset_aom_legal_owner. C’est aussi renseigné à la main à travers le backoffice.

**Ce mécanisme est différent de la couverture géographique prédécente**. On peut par exemple avoir :

- un jeu de données avec une *couverture territoriale* nationale mais plusieurs régions *référentes légales* (cas du JDD des TER),
- ou à l’inverse, une couverture locale (exemple des autocars scolaires de l’ile de Ré, couverture multi-communale, mais dont le représentant légal est la région [https://transport.data.gouv.fr/datasets/horaires-theoriques-et-temps-reel-du-reseau-ile-de-re-la-rochelle-nouvelle-aquitaine-3-3e-et-scolaires-gtfs-gtfs-r](https://transport.data.gouv.fr/datasets/horaires-theoriques-et-temps-reel-du-reseau-ile-de-re-la-rochelle-nouvelle-aquitaine-3-3e-et-scolaires-gtfs-gtfs-rt))

Un dataset peut à la fois avoir des régions et des AOM comme représentants légaux :

```sql
select dalo.dataset_id, d.custom_title, dalo.aom_id, a.nom, drlo.region_id, r.nom from dataset_aom_legal_owner dalo
join dataset d on dalo.dataset_id = d.id
join dataset_region_legal_owner drlo on dalo.dataset_id = drlo.dataset_id
join aom a on dalo.aom_id = a.id
join region r on drlo.region_id = r.id ;
```

Fonctionnellement, ce mécanisme de représentant légal est peu utilisé : on dirait qu’il sert surtout à la page de statistiques, pour savoir quelle est notre couverture territoriale.

# Les AOM

**Les AOM ont une géométrie propre**, et appartiennent à une région (champ `région_id`). Ils ont aussi une commune principale, et un département, mais qui sont stockés en propre sans faire référence à ces objets. Ils sont typés en fonction de leur forme juridique : syndicat mixte, communauté d’agglomération, comnunauté de communes, métropole… il y a un seul cas où un AOM a une couverture régionale, c’est pour Ile de France Mobilités.

C’est une implémentation à améliorer :

- En réalité, l’AOM appartient à des collectivités locales (ECPI, région…) : il faudrait peut-être indiquer quelle est la collectivité locale référente en plus de la région, et plutôt qu’avoir  une géométrie propre, l’AOM pourrait l’hériter de ces collectivités locales.
- Normalement, la “Région” est une AOM comme une autre = cars interurbains avec couverture régionale.  IDFM est différent d’une AOM Région juste par le fait qu’elle organise à la fois les transports interurbains et urbains. Il faudrait éventuellement revoir le mécanisme de représentant légal avec deux tables séparées.

# Les territoires / collectivités territoriales

On a ces territoires, chacun avec une table différente, qui ont une géométrie stockées sur le PAN :

- Les régions
- Les départements (qui appartiennent à une région)
- Les communes (qui appartiennent à un département)

Les EPCI ont également une table, mais celle-ci est rudimentaire (et non utilisée ?) : elle ne contient pas d’information géographique, les EPCI n’y sont pas typés (métropole, etc), c’est juste une liste de communes stockées dans un varchar (bizarre).

# Place

Places est un fourre-tout, les types :

- communes
- aom
- regions
- feature
- mode.

Pas d’info géographique, c’est un catalogue de noms, qui sert pour la recherche.

# Les ressources et les conversions GTFS → geojson

Les resources en soit n’ont pas d’info géométrique directement en BDD, mais peuvent:

- Soit être un fichier géographique ( geojson), et dans ce cas, on affiche une carte non pas sur la page de la resource, mais celle du jeu de données. (Question : il se passe quoi quand il y a plusieurs geojson sur le même dataset ?)
- Soit être un type de fichier qui contient de l’information géographique : GTFS…
- Soit être un fichier absolument pas géographique.

**Dans le cas d’une ressources GTFS, il y a une conversion automatique vers du geojson qui est stocké sur le cloud, ce qui permet d’afficher la carte des lignes et des arrêts sur la page de détails de la resource.**

Le fichier Geojson est généré à travers un job récurrent, puis stocké dans le cloud, et l’URL est enregistrée dans la table `data_conversion`, qui fait le lien entre une `resource_history` et cette URL. Il ne s’agit pas d’information géographique directement en base de données : on n’a que le lien vers le fichier sur la BDD, on ne peut donc pas se servir de cela pour des requêtes géographiques.

# Les extracteurs de données géographiques

**En revanche, on a des convertisseurs qui vont aller extraire de l’information géographique des resources pour les stocker dans la base de données, dans des tables avec des colonnes géométriques,** avec deux grands mécanismes :

- L’extracteur d’arrêts GTFS, qui alimente la table `gtfs_stops`, affichée dans la carte des arrêts GTFS
- Les extracteurs IRVE, BNLC et ZFE, qui vont alimenter la table `geo_data`, affichée sur la carte d’exploration.

Il y a aussi une carte `GTFS_trips`, mais pour moi, c’est peu clair : chez moi elle est vide…

## Les arrêts GTFS

Il s’agit d’une table, avec :

- Des colonnes séparées pour longitude et latitude : on ne stocke pas une géométrie, mais des floats
- Des informatinos concernant l’arrêt
- La référence à un data_import_id, qui fait lui-même référence à une resource_history, donc à une resource

On stocke également des clusters d’arrêts pour chaque niveau de zoom pour faciliter l’affichage de la carte, mais il ne font référence à rien : c’est juste des coordonnées avec un nombre d’arrêts sous-jacents, mais qui ne font pas référence à ceux-ci.

## Les geodata : données géographiques IRVE, BNLC et ZFE

On a une table geodata, qui contient les points ou polygones des IRVE, BNLC et ZFE :

- Pour le coup il y a une vraie colonne «géométrique», pour pouvoir stocker soit un point soit un polygone
- UNe payload JSON qui renseigne sur le contenu du point
- Ça appartient à la table geodata_import, qui ensuite est reliée aux resources.

## Les infos temps réel (GTFS-RT)

Aucune idée de comment ça marche et où / comment c’est stocké et ça remonte.

# Les mécanismes de recherche graphique

À compléter.

# L’accès aux données géographiques par API

Les API géographiques documentées : [https://transport.data.gouv.fr/swaggerui](https://transport.data.gouv.fr/swaggerui)

- Les AOM peuvent être recherchés par coordonnés géographiques, exemple GET`[https://transport.data.gouv.fr/api/aoms?lon=-0.5342&lat=44.7441](https://transport.data.gouv.fr/api/aoms?lon=-0.5342&lat=44.7441)` (Mais on n’a pas le geojson dans la réponse)
- On peut avoir une liste du geojson de tous les AOM via `https://transport.data.gouv.fr/api/aoms/geojson`
- On peut aussi avoir le geojson d’un dataset.

**Il n’y a pas de recherche de dataset dans l’API, ni par nom, ni par localité (nom de commune, code INSEE), ni par localisation (boundbox, point, périmètre).**

**Les cartes d’exploration s’appuient sur des API non documentées :**

- Les geodata sont accessibles à travers l’endpoint `/geoquery`. Exemple : [https://transport.data.gouv.fr/api/geo-query?data=irve](https://transport.data.gouv.fr/api/geo-query?data=irve)
- Les arrêts GTFS sont disponibles sous `/explore/gtfs-stops-data` (en mettant plein d’arguments spécifiques, sinon ça crashe)
