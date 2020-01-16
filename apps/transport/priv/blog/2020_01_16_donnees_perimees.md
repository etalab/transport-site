Si une grande partie du territoire dispose désormais d'information ouverte sur transport.data.gouv.fr, cette information voyageur n'est pas toujours relayée par les réutilisateurs. Une des raisons principales, au delà de la qualité, est le maintien à jour en continu des données.

# Données périmées, données inutilisées !


## Les réutilisateurs ont besoin d'une information à jour

Pour maintenir une information de qualité, les réutilisateurs de données d'information voyageur ont besoin de sources fiables. Deux critères de fiabilité s'imposent : 
1. la qualité des données elles-mêmes ;
2. la période de validité des données.

Si transport.data.gouv.fr dispose d'un validateur permettant de tester les deux critères, la période de validité est un enjeu au moins aussi complexe que la qualité des données en elles-mêmes.

### Bien guider l'usager

Les réutilisateurs attirent les usagers grâce à la qualité de l'information qu'ils relaient. Si le service de bus a changé entre hier et aujourd'hui, mais que mon application préférée n'a pas eu cette information, elle ne pourra pas me permettre de me rendre facilement où j'ai besoin d'aller.

**Dans beaucoup de cas d'absence de mise à jour, le réseau n'a pas évolué,** ou bien de manière très marginale. C'est pourquoi certains réutilisateurs continuent d'afficher les données de la semaine précédente par exemple, avec une mention indiquant qu'elles ne sont peut-être plus valables.

Lorsque le réseau de transport n'a pas été mis à jour sur transport.data.gouv.fr, trois possibilités se présentent à l'usager : 
1. le réutilisateur a prolongé les horaires précédents, et les nouveaux horaires sont en effet les mêmes (cas majoritaire) : **le trajet se passe normalement pour l’usager ;**
2. le réutilisateur a simplement retiré l’informationn voyageur pour ce réseau : **aucune information pour l’usager ;**
3. le réutilisateur a prolongé les horaires précédents, mais les horaires avaient changé : **l’usager reçoit une mauvaise information.**

**L'usager non informé ou mal informé peut changer de mode d'information,** entraînant une perte de fréquentation pour les réutilisateurs. Mais **l'usager peut aussi penser que les transports en commun ne sont pas un mode de transport fiable** car ce matin là, il avait un entretien d'embauche, un train à prendre, ou un autre événement qu'il a loupé à cause de cette absence de mise à jour. Il reprendra alors son véhicule personnel.

Tout le bénéfice de l'information voyageur ouverte pour permettre une meilleure accessibilité et donc diminuer l'usage des modes de transports les plus polluants est donc perdu.  

### Calculer l'itinéraire pour demain

L'autre exigence importante des usagers est le calcul d'itinéraire pour demain, ou la semaine prochaine par exemple.

Ceci ne demande plus aux producteurs de délivrer des données à jour, mais plutôt d'**avoir des données qui sont toujours valables au moins quelques jours après.** Plus concrètement, si un jeu de données décrivant les horaires d'un réseau est valable jusqu'au 31 décembre, il faut proposer une mise à jour le 15 décembre, voire avant pour permettre la majeur partie des calculs d'itinéraires faits en prévision.

Ceci nécessite dans le cas de modification du réseau, la création d'un jeu de données de transition, qui contient à la fois des données du nouveau et de l'ancien réseau, ou bien une publication anticipée du nouveau réseau.

## 82% des réseaux référencés sur transport.data.gouv.fr sont à jour

### Statistiques

Avec le changement d'année 2019-2020, un certain nombre de fichiers sont arrivés à leur date d'expiration. L'occasion de disposer de quelques statistiques sur les manques de mise à jour.


| Données périmées depuis              | Nombre total d'AOMs où les données ne sont pas à jour | Renouvellement du réseau et/ou du contrat en cours | Difficulté technique constatée |
| :----------------------------------- | :---------------------------------------------------: | :------------------------------------------------: | :----------------------------: |
| Moins de 2 jours                     |                           4                           |                                                    |                                |
| Plus de 2 jours, moins de 2 semaines |                          12                           |                                                    |                                |
| Plus de 2 semaines, moins de 6 mois  |                           2                           |                         2                          |                                |
| Plus de 6 mois, moins de 1 an        |                           3                           |                                                    |               1                |
| Plus de 1 an                         |                           3                           |                                                    |               1                |

Cependant, si l'on prend en compte le nombre d'AOMs pour revenir en proportions, on constate que 82% des AOMs qui ont publié individuellement ont aujourd'hui des données à jour, et **seulement 6% ont des données périmées depuis plus de 2 semaines.**


![Proportion des données à jour](/blog/donnees_perimees/MAJ-article-maj-de.png)


### Peu de données sont à jour en réelle continuité
Malgré cette faible portion de données périmées, si l'on s'intéresse aux jeux de données maintenus à jour à tout instant, ils représentent une portion assez faible des données exposées car cela demande une mise à jour avant la date de péremption. Rares sont les AOMs qui publient dans ces conditions.

Sur la période autour du changement d'années, les données de 5 AOMs qui publient individuellement ont été maintenues à jour avec une continuité réelle. Ceci représente **27% des AOMs** dont les données ont terminé leur validité sur la période.

On constate que **la mise à jour effective se fait le plus souvent entre 2 et 4 semaines après la péremption du fichier précédent.** Cependant, les réutilisateurs et usagers ont besoin d'une mise à jour au moins quelques jours, voire quelques semaines avant la péremption du fichier précédent.

## Il est possible d'améliorer facilement les procédés de mise à jour
Face à ces difficultés pour maintenir l'information à jour, il existe des moyens de se préparer et de rendre ceci bien plus simple.

### Personne n'est indispensable

Dans un nombre important de mises à jour non-effectuées, il s'avère que la personne en charge précédemment a quitté ses fonctions. Si la mission n'est pas bien transmise ou que les droits d'accès ne sont pas accordés au successeur, il ne peut pas mettre à jour.

Il n'est pas sûr que tout repose sur une seule personne. Pour la partie technique, nous remarquons assez peu de disfonctionnement. En revanche, pour *déposer le fichier sur la plateforme*, les problèmes sont nombreux. Mais une mesure très simple a raison de tous ces problèmes :
> **Toujours avoir au moins deux personnes membres de l'organisation sur data.gouv.fr**

D'une part, avec plusieurs membres, si l'un n'est pas présent, l'autre peut soit publier directement les données, soit nommer un autre membre pour le faire, ce qui garantit une continuité simple des accès.
D'autre part, avec deux inscrits, si l'un des deux quitte son poste, l'autre est au fait de l'existence de la plateforme et sait la manipuler un minimum.

### Réduire le nombre de personnes nécessaires
Sur un certain nombre de territoires, l'actualisation passe par un fichier qui transite par plusieurs boîtes mail avant d'être finalement publié en open data. Si l'un des correspondant tarde, le nouveau fichier n'arrive pas avant la fin de la validité du prédédent.

![Membres de l'organisation sur data.gouv.fr](/blog/maj-datagouv.png)

*Le schéma de l'état actuel est relativement simple sur cette image, dans certains cas, le fichier peut passer par 4 personnes avant publication.*

Pourtant, il est possible de publier les données immédiatement après leur production ce qui réduit la charge de travail mais surtout diminue le délai de mise à jour.

> **Permettre au délégataire ou à son prestataire de publier directement les données**

Dans la plupart des cas, le membre de l'AOM qui a les droits sur le compte n'a pas la capacité d'analyser le fichier GTFS, ni même de le manipuler. Il n'opère pas de véritable contrôle. De plus, en ayant un compte avec des droits d'administration supérieurs, le responsable de l'AOM peut vérifier que l'opérateur ne publie pas d'autres données.


## Mise à jour impropre

### Une donnée, un fichier, plusieurs références
Une mauvaise pratique assez répandue rend les mises à jour parfois difficiles : la multiplication des emplacements d'un même fichier. Prenons l'exemple d'une collectivité *moyenne*, elle demande à son délégataire un fichier et :
1. le stocke pour ses archives en privé ;
2. le dépose sur sa plateforme locale d'open data ;
3. l'envoie à la Région pour alimenter le calculateur régional ;
4. le dépose pour alimenter transport.data.gouv.fr.

Il y a donc 4 exemplaires du côté de la collectivité, plus celui stocké dans les bases du délégataire. Toute mise à jour se transforme en 5 mises à jour, avec de fortes chances que tôt ou tard, l'une ou l'autre soit oubliée.

![Schema](/blog/maj-publi.png)

> **Déposer le fichier sur un seul emplacement où il est maintenu à jour par le producteur, et y faire référence grâce à son url**

La bonne pratique consiste à stocker les données sur un seul et unique serveur, et à les référencer. Premier avantage : tous les acteurs sont toujours en possession de la même version. Deuxième avantage : **toute mise à jour des données est immédiatement répercutée pour tous, sans aucune manipulation supplémentaire.** De nombreux acteurs ont déjà mis cette pratique en place, elle a d'excellents résultats.


### Une mise à jour, pas un nouveau fichier distinct
Outre l'absence de mise à jour, de nombreux cas montrent une mise à jour impropre. Il s'agit de l'ajout des nouvelles données, non pas comme mise à jour des données précédentes, mais comme nouveau jeu de données distinct. Ceci pose un problème majeur : **rien n'indique qu'il s'agit d'une mise à jour en termes d'information.** Il n'y a donc aucune continuité dans les données pour les réutilisateurs, **aucun traitement entièrement automatisé n'est possible.**

À l'écoute de ceux qui publient, trois raisons principales les poussent à publier de nouveaux jeux au lieu de mettre à jour :
1. ils ne connaissent pas la procédure de mise à jour ;
2. ils disposent d'une plateforme open data locale qui ne gère pas bien la mise à jour ;
3. ils pensent que la mise à jour va effacer les données précédentes et donc ne veulent pas s'en servir avant la date butoir, ou bien, ils veulent garder un historique même après la fin de la validité.

*Les motifs 1 et 3 ne concernent que les mises à jour manuelles, qui devraient exister de moins en moins grâce au passage vers plus de références et moins de fichiers déposés.*

Les deux premières raisons reposent sur des difficultés techniques et peuvent donc être résolues en les informant ou en demandant à leur prestataire de plateforme des corrections, le troisième motif est plus complexe.

## Deux situations, deux méthodes de mise à jour

Dans l'interface entre transport.data.gouv.fr comme sur data.gouv.fr, il existe deux manières de gérer les mise à jour.

#### Le fichier précédent ne sera plus utile : mise à jour
Cette procédure est une mise à jour simple, elle remplace l'ancien fichier par celui qui est déposé : elle écrase les données. Elle n'est donc pertinente que lorsque le jeu de données précédent n'est plus utile, c'est-à-dire : 
1. lorsque le jeu de données précédent est déjà expiré et n'est donc plus utile ;
2. dans le cas d'une mise à jour anticipée, lorsque le nouveau jeu de données reprend en partie l'ancien.

#### Le fichier précédent restera utile quelques temps : ajouter une nouvelle ressource
Cette procédure permet non pas de remplacer le fichier existant, mais d'ajouter une ressource (un fichier) au jeu de données. Grâce à cette possibilité, on peut lier deux fichiers en indiquant explicitement le lien.

Ceci permet aux réutilisateurs de faire le changement au bon moment. Par exemple, si le fichier est valide jusqu'au 31 décembre, il est possible d'ajouter le fichier valide à partir du 1er janvier dès le 15 décembre comme nouvelle ressource. Les deux fichiers seront exposés sur transport.data.gouv.fr.

## 3 conseils pour une autorité organisatrice de la mobilité

1. Ajouter son producteur de données à son compte data.gouv.fr.

2. Utiliser de multiples référence (avec une url) à **un seul et même fichier.**

3. Mettre à jour les données en amont de leur fin de validité, en faisant attention à la continuité des données.
