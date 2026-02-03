# Nouveautés du PAN

Retrouvez sur cette page les principales nouveautés chaque mois.

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
