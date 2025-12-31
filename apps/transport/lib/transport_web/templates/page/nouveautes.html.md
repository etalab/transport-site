# Nouveautés du PAN

Retrouvez sur cette page les principales nouveautés chaque mois.

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
