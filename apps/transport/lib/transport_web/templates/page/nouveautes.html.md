# Nouveautés du PAN

Retrouvez sur cette page les principales nouveautés chaque mois.

## Septembre 2026

### 🚌 NeTEx
- Rapport de validation : erreurs triées par criticité décroissante ;
- Affichage de la version de la XSD NeTEx utilisée pour la validation.

### ♻️ Réutilisations
- Nouvelle présentation des réutilisations sur la page d'un jeu de données : plus lisible, avec le nombre de réutilisations dans le menu et un message lorsqu'il n'y en a aucune ;
- Le message invitant à partager ses réutilisations est mieux mis en valeur.

### 🔒 Sécurité
- Chiffrement des cookies de session (une reconnexion est nécessaire une fois).

### 🛠️ Backoffice
- Actions sur les jeux de données regroupées dans un menu contextuel ;
- Recherche de jeux de données plus pratique : filtres préconfigurés plus compacts et combinables avec la recherche texte.

### 🐞 Corrections
- Correction de boutons qui n'apparaissaient plus sur certaines pages.

### ⚙️ Technique & maintenance
- Mise à jour du fichier `.proto` GTFS-RT ;
- Revue de la détection des opérateurs GBFS ;
- IRVE dynamique : interrogation des flux limitée au serveur web de production ;
- Refactorisation de la page de détails des jeux de données et réduction de la duplication de code ;
- Corrections d'erreurs remontées par Sentry.

## Août 2026

### 🚌 NeTEx
- Choix automatique de la XSD selon la date de publication du fichier, en suivant les versions du profil France :
  - profil France 2.4 : XSD NeTEx 1.3.2 ;
  - profil France 2.5 (prévu pour décembre 2026) : XSD NeTEx 2.0.0, appliquée après une période de grâce de 6 mois, à partir de juin 2027 ;
- Extraction de la date de publication dans les métadonnées NeTEx ;
- Correction de l'affichage du rapport lorsque la ressource n'est pas valide.

### 📧 Notifications
- Nouveau texte de l'e-mail d'expiration des données, plus concis et qui rappelle l'impact pour l'information voyageur.

### ⚡ IRVE
- Rapport de consolidation : nouvelle colonne indiquant le statut de chaque ressource (nouvelle, déjà connue, supprimée de data.gouv.fr).

### 🚲 Vélos et trottinettes en libre-service
- Correction de l'opérateur associé au flux GBFS Leo&Go.

### ⚙️ Technique & maintenance
- NeTEx : stockage uniforme des résultats de validation (Parquet), écrits directement depuis un DataFrame, et correction de l'archivage des anciennes validations ;
- NeTEx : choix de la XSD transmis au validateur enRoute Chouette Valid ;
- Consolidation IRVE : une seule passe de correction des coordonnées ;
- Extraction mensuelle des téléchargements par format pour l'ART ;
- Mises à jour de sécurité, corrections de documentation et stabilisation des tests.

## Juillet 2026

### 🚗 Covoiturage
- Textes d'aide dédiés aux lignes de covoiturage dans la recherche ;
- Meilleur affichage des instructions relatives aux formats de données dans les résultats de recherche.

### 🚌 GTFS
- Mise à jour des règles du validateur MobilityData (version 8.0.1).

### ⚡ IRVE
- Rapport de consolidation plus lisible : statuts plus précis et messages d'erreur explicites.

### 🚲 Vélos en libre-service
- Ajout de Yélo (La Rochelle) aux opérateurs connus.

### 🔒 Sécurité
- Mise en place d'un scanner de vulnérabilités et mises à jour des librairies concernées.

### ⚙️ Technique & maintenance
- Consolidation IRVE : lecture unique de chaque fichier avec vérifications avant validation, export de la base par lots, meilleure gestion des erreurs d'envoi vers S3 ;
- Fin de l'utilisation de TimescaleDB pour les métriques du proxy ;
- Suppression de la librairie ExVCR des tests ;
- Mise à jour du protobuf GTFS-RT.

## Juin 2026

### ⚡ IRVE
- Validateur à la demande : lien permanent vers les résultats de validation, pour les partager facilement ;
- Validateur à la demande : avertissement lorsque les coordonnées semblent inversées (latitude et longitude) ;
- Consolidation : redressement automatique des coordonnées inversées, qui plaçaient environ 15 % des points de charge dans l'océan ;
- Consolidation : la puissance nominale n'est plus affichée avec des zéros superflus (`22` au lieu de `22.00000000`) ;
- Arrêt de la consolidation « brute » non validée, remplacée par la consolidation validée et dédoublonnée.

### ⚙️ Technique & maintenance
- Suppression du code de la consolidation IRVE brute ;
- Mise à jour du protobuf GTFS-RT ;
- Stabilisation des tests.

## Mai 2026

### ⚡ IRVE
- Règle de validation des adresses e-mail plus stricte, alignée sur Validata.

### 🔌 API & temps réel
- API : le `requestor_ref` des flux SIRI est exposé dans un champ dédié.

### 🚲 Vélos en libre-service
- Ajout de Yégo aux opérateurs GBFS connus.

### ⚙️ Technique & maintenance
- Modernisation de l'outillage front-end (JavaScript, icônes FontAwesome 7, feuilles de style) : DeckGL, Vega, migration SCSS vers `@use` ;
- Patchs de sécurité JavaScript ;
- Configuration des validateurs GTFS et GBFS lue à l'exécution plutôt qu'à la compilation ;
- Suppression de code mort : ancien agrégateur IRVE dynamique du proxy, support expérimental SIRI ;
- Scripts de diagnostic : analyse des doublons du consolidé IRVE dynamique, vérification des flux SIRI.

## Avril 2026

### 🚌 NeTEx
- Carte des arrêts et des tracés sur la page des ressources NeTEx ;
- Détection des grandes fonctionnalités NeTEx utilisées par une ressource, selon les sous-profils du profil France ;
- Métadonnées NeTEx (modes, réseaux, dates de validité, statistiques) disponibles dans l'API ;
- Prise en compte du NeTEx dans le suivi de la fraîcheur et de la qualité des données (statistiques, pages AOM, backoffice) ;
- Rapport de validation plus compact lorsque tout est valide.

### ⚡ IRVE
- Le validateur IRVE à la demande utilise désormais le validateur de transport.data.gouv.fr, le même que pour la consolidation nationale ;
- Nouveau moteur d'agrégation des flux IRVE dynamiques.

### ♿ Accessibilité
- Navigation au clavier dans le menu principal.

### 🛠️ Backoffice
- Nouvelle page de suivi des tâches de fond, avec filtres et panneau de détails.

### ⚙️ Technique & maintenance
- Mise à jour majeure de l'outillage JavaScript : build, ESLint 10, formatage avec Prettier ;
- Proxy : possibilité de surcharger les en-têtes de réponse des flux S3 ;
- IRVE : résumé de validation exploitable, base du nouveau validateur à la demande ;
- Mise à jour du protobuf GTFS-RT ;
- Nettoyage : suppression de `Mix.env()` à l'exécution, du code de conversion GTFS vers NeTEx inutilisé, correction d'une tâche planifiée ;
- Stabilisation de tests fragiles.

## Mars 2026

### 🏛️ Identité
- Nouveau logo et nouvelle dénomination « Ministère des Transports ».

### 🚌 NeTEx
- Nouveau rapport de validation, y compris pour la validation à la demande ;
- Téléchargement du rapport de validation au format CSV ou Parquet ;
- Statistiques sur les ressources NeTEx : réseaux, lignes, lieux d'arrêt et zones d'embarquement ;
- Documentation en ligne des règles du profil France vérifiées par le validateur ;
- Révision des règles du profil France.

### 📡 GTFS-RT
- Avertissement dans le rapport de validation lorsque les identifiants ne correspondent pas entre le GTFS et le GTFS-RT ;
- Notification des producteurs lorsque la validation échoue avec une erreur fatale.

### 📊 Statistiques
- Premier tableau de bord Metabase sur les données de transport en commun, affichable en plein écran.

### 🧭 Navigation
- Barre de recherche sur les pages des jeux de données et des ressources ;
- Menu principal amélioré, notamment sur mobile ;
- Badge de notifications plus lisible ;
- Date de dernière mise à jour d'une ressource affichée dès sa première historisation ;
- Un clic sur le cœur d'un jeu de données suivi mène à la gestion de ce jeu de données dans l'espace producteur ou réutilisateur ;
- Nom de l'entreprise (à partir de son numéro SIREN) affiché sur la page des jeux de données ;
- Retrait de la couche des parkings relais dans l'explorateur, la base nationale ayant été déréférencée.

### ⚡ IRVE
- Consolidation dédoublonnée : suppression de tous les doublons restants ;
- Qualicharge est désormais la source prioritaire lors du dédoublonnage ;
- Exclusion des jeux de données produits par transport.data.gouv.fr de la consolidation.

### 🛠️ Backoffice
- Association manuelle de deux ressources d'un jeu de données ;
- Export CSV des jeux de données ;
- Export des ressources enrichi (ressources associées, nom de l'entreprise).

### ⚙️ Technique & maintenance
- Création et mise à jour quotidienne des entreprises à partir des numéros SIREN ;
- Proxy : affichage des tailles totales en mémoire et sur disque dans le backoffice ;
- Rafraîchissement de l'index de recherche en mémoire depuis le backoffice ;
- IRVE : configuration des jeux de données prioritaires du dédoublonnage dans un fichier dédié, prise en compte du flux dynamique dans les statistiques d'unicité des points de charge ;
- PostgreSQL 18 et TimescaleDB 2.23 en intégration continue, Stylelint 17 ;
- Documentation du test de disponibilité et de la mise à jour des règles NeTEx ;
- Stabilisation des tests.

## Février 2026

### 🚌 NeTEx
- Identification et notification aux producteurs des ressources NeTEx expirées ;
- Extraction et affichage de métadonnées dont les modes de transports, les réseaux et les dates de validité d'une ressource NeTEx ;
- Rapport de validation: erreurs XSD regroupées par message ;
- Téléchargement du rapport de validation ;
- Corrections & maintenance.

### ⚡ IRVE
- Validateur IRVE : autoriser plusieurs espaces dans les coordonnées ;
- Consolidation :
  - Consolidation IRVE : création et publication du fichier dédoublonné ;
  - Renommage du rapport de consolidation IRVE ;
  - Suppression des pdc avec id_pdc_itinerance "non concerné" de la consolidation IRVE dédoublonnée ;
  - Consolidation IRVE Remontée d’informations supplémentaires ;
  - Identification des datasets présents dans le consolidé datagouv et non chez nous.

### 🔍 Recherche
- Optimisation : recherche en mémoire ;
- Recherche par sous-type avec index en mémoire.

### 📦 Produit
- Rapport opérationnel (suivi global + détaillé) ;
- Ajout d'un menu de navigation dans le détail d'une ressource ;
- Conversion GeoJSON moins mise en avant ;
- Les ressources GTFS Flex expirées d'un dataset sont désormais identifiées comme telles.

### ⚙️ Ops
- Montée de version PostgreSQL (de 14 à 18) ;
- Actualisation de la configuration ZFE ;
- Ajout de la Suisse dans administrative_division.

## Janvier 2026

### ⚡️ Consolidation IRVE (Infrastructures de Recharge de Véhicules Électriques)
* **Amélioration du processus PAN** : Optimisation du script de consolidation pour la production, incluant un pré-processing des fichiers avant validation.
* **Qualité des données** : Transformation systématique en UTF-8, gestion des tabulations dans les coordonnées et autorisation des espaces pour les coordonnées XY.
* **Monitoring et Reporting** : Mise en place d'un reporting actionnable pour identifier les points de charge (PDC) manquants et ajout de logs détaillés au début des jobs.
* **Export et Performance** : Possibilité d'exporter la base de données IRVE et ajustement des paramètres de parallélisation et de timeout.

### 🔍 Recherche et Navigation
* **Recherche par sous-types** : Nouveau filtre permettant de chercher par sous-type de données dans le catalogue.
* **Autocomplete** : Amélioration de l'ordre des résultats et du comportement de la touche "Entrée".
* **Fil d'ariane** : Mise à jour de la navigation dans l'Espace Producteur pour une meilleure expérience utilisateur.

### 👤 Espaces Utilisateurs (Producteur & Réutilisateur)
* **Gestion des problèmes urgents** : Affichage des problèmes dans l'espace réutilisateur, ajout de dates de validité et possibilité de trier les colonnes.
* **UX/UI** : Ajustement de l'affichage des informations importantes et ajout d'un menu interactif pour les nouveautés.
* **Discussions** : Amélioration du scroll lors du chargement et liens directs vers les discussions sans réponse.

### 📊 Statistiques et Reporting
* **Visualisation** : Affichage des statistiques de téléchargement sur l'année courante et précédente avec ajout de boutons d'accès rapide en haut de page.

### 🇪🇺 Validation NeTEx
* Quelques règles spécifiques au profil France sont désormais implémentées.

### ⚙️ Technique et Backend
* **Proxy S3/HTTP** : Mise en place d'un cache sur disque avec vérification ETag pour optimiser les performances de téléchargement.
* **Maintenance** : Correction de la gestion de la taille des hypertables TimescaleDB et mises à jour majeures des dépendances (Phoenix, LiveView, Explorer).
* **Tâches asynchrones** : Refactorisation des jobs d'expiration de données et de notification d'indisponibilité des ressources (avec gestion des tentatives).

## Décembre 2025

### ⚡️ IRVE
* Consolidation IRVE brute v2 : validation simple, insert en base, pas de dédoublonnage

### 🚀 Espace Producteur & Expérience Utilisateur
* **Refonte fonctionnelle :** Ajout de statistiques de téléchargement (avec export CSV), gestion des discussions sans réponse et affichage des indicateurs de validité.
* **Améliorations UI/UX :** Migration de formulaires vers **LiveView**, refonte du CSS, ajout d'icônes et mise en place de pastilles de notification pour les problèmes urgents.

### 🔍 Recherche
* **Recherche & Autocomplete :** Amélioration de la recherche par format de données et par offre de transport. Ajout de raccourcis clavier et de la recherche par adresse sur les cartes d'exploration.

### 🛠 Validation & Qualité des Données
* **Standard GTFS :** Intégration du validateur **MobilityData** et support des extensions **GTFS-Flex** et Fares v2.
* **Performance technique :** Passage au **stockage binaire** pour les résultats de validation NeTEx et optimisation des validateurs JSON Schema et TableSchema.

### 🔌 Proxy & Flux Temps Réel
* **Proxy Unlock :** Support des flux **GBFS** en plus des **GTFS-RT** avec un meilleur suivi des métriques dans le backoffice.

### 📧 Notifications & Backoffice
* **Communication :** Intégration du **DSFR** (Design System de l'État) pour les e-mails et ajout d'un outil de prévisualisation dans le Backoffice.

### ⚙️ Technique & Infrastructure
* **Mises à jour :** Montée de version vers **Elixir 1.19.4** et mise à jour des dépendances critiques.
* **Optimisations base de données :** Amélioration des plans d'exécution PostgreSQL, ajout d'index de performance et réduction de l'empreinte mémoire pour les grosses ressources.
* **Maintenance :** Suppression de CircleCI et réorganisation du code source (déplacement de l'application `datagouvfr`).

## Novembre 2025

### 🚀 Nouvelles fonctionnalités
- **Gestion PASSIM** : Importation des offres PASSIM et renseignement des autorités organisatrices de la mobilité (AOM) associées.
- **Validation IRVE** : Optimisation majeure de la validation des données IRVE via un pipeline DataFrame vectorisé pour de meilleures performances.
- **API & Tags** : Ajout de la possibilité d'utiliser des `custom_tags` via l'API.
- **Export Backoffice** : Ajout des informations relatives aux offres de mobilité dans les exports BO.
- **Données géographiques** : Mise à jour administrative 2025 pour les EPCI, les communes et les AOM.

### 🛠️ Améliorations techniques & Performance
- **Maintenance Base de données** : Passage d'un `VACUUM FULL` quotidien (au lieu de hebdomadaire) pour optimiser les performances disque.
- **Validation** : Nouveau système de stockage des résultats synthétiques de validation et utilisation de `MultiValidation.digest`.
- **Nettoyage automatique** : Introduction de nouveaux jobs de nettoyage (`CleanMultiValidationJob`, `CleanOnDemandValidationJob`) et correction du cleanup des conversions NeTEx.
- **Optimisation des logs** : Réduction du volume global des logs pour une meilleure lisibilité.
- **Stabilité CI** : Mise en place de contournements pour éviter les deadlocks lors des tests d'intégration.
- **Simplification du modèle** : Suppression définitive des colonnes obsolètes `aom_id`, `region_id` et de la table `dataset_communes` au profit de la couverture spatiale.

### 📈 Interface & Expérience Utilisateur
- **Gestion des AOM** : Affichage du nombre de ressources sur la page AOM et amélioration du sélecteur de responsables légaux pour retirer une AOM depuis les offres.
- **Notifications** : Correction de la page de notifications pour les producteurs.

### 🐞 Corrections & Maintenance
- **Sécurité** : Mise à jour de la dépendance `js-yaml` (4.1.1).
- **Robustesse** : Amélioration de la stabilité de plusieurs tests (LEZ, expiration des notifications, validations à la demande).

## Octobre 2025

### 🎫 GTFS Fares V2
- Validateur GTFS : Support de fares V2
- Détails d'un GTFS : infos si fares v2

### 🔍 GTFS diff
- GTFS Diff explications supplémentaires pour agency.txt
- GTFS-Diff - ajout primary keys pour fare_rules

### 🚏 GTFS Flex
- Lien vers validateur GTFS-Flex dans nouvel onglet
- GTFS-Flex : change règle de détection

### ♻️ Réutilisations
- Page réutilisations : modifications des traductions
- Réutilisations : lien vers Espace réutilisateur
- Modification contraste de la couleur verte des réutilisateurs
- Correction couleur des images pour réutilisateurs
- Accueil : suppression des logos des réutilisateurs
- Accueil : infos réutilisateurs
- Ajustements UX pour réutilisateurs

### ⚡ IRVE
- Stockage des fichiers IRVE valides et leurs points de charge en base de données
- Primitives pour la validation des IRVE statiques

### 🗺️ Divisions administratives & couverture spatiale
- Rajout de Monaco à la table des divisions administratives
- Page stats en utilisant la couverture spatiale
- DB.Dataset.count_coach : utilise couverture spatiale
- Mise à jour 2025 pour Commune et EPCI
- Supprime aom_id et region_id de dataset

### ⚖️ Responsables légaux
- Retravaille AOMSController avec responsables légaux
- StatsHandler : utilise uniquement responsables légaux
- AOMs avec données : uniquement responsables légaux

### 🚀 Performance
- Temps de chargement des résultats de validation

### 🛠️ Maintenance technique
- Stabilisation de quelques tests
- Resource#details: Suppression double binding MultiValidation
- Ops test : ajout de Sendgrid dans les SPF
- Mise à jour Cachex v4
- Mise à jour des dépendances
