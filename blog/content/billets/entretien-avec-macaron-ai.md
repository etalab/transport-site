---
title: Entretien avec Macaron.ai
date: 2021-10-08T13:40:18.018Z
tags:
  - réutilisation
  - qualité des données
  - retour d'expérience
description: "Il y a près d’un an, l’équipe transport.data.gouv.fr a croisé le
  chemin d’une jeune start up qui souhaitait mettre l’open data au cœur de sa
  stratégie pour résoudre la problématique du stationnement en milieu urbain :
  Macaron. Ils proposent désormais un schéma de données pour harmoniser les
  données de stationnement en voirie qui sera très prochainement référencé sur
  schema.data.gouv.fr. Leur travail en collaboration avec des réutilisateurs et
  des producteurs de données est très intéressant, c’est pourquoi nous vous
  proposons une interview de leur Chief Technical Officer : Abderrahmane
  Bouroubi."
images:
  - /images/macaron-c7b81ada7083912b2ca064eba829903e.png
---
**Bonjour Abderrahmane, est-ce que tu peux te présenter ?**

Je suis Abderrahmane Bouroubi, CTO de Macaron, la startup qui travaille à résoudre le problème du stationnement dans les villes. 

J’ai un diplôme d’ingénieur en informatique et un Master 2 en Conception et Analyse de Système d’Information. J’ai rejoint Macaron après avoir passé 3 ans chez Capgemini en tant que consultant et 3 ans chez GFI Informatique en tant que Team Lead.

Chez Macaron, mon rôle est de concevoir les solutions aux problématiques complexes du stationnement et dans un second temps de recruter les meilleurs talents pour faire évoluer notre équipe. 

![](/images/image.jpg)

**Quelle est l’activité de Macaron ?**

Notre objectif est de simplifier l’expérience des automobilistes dans leur recherche de places de stationnement. Nous utilisons l’intelligence artificielle pour leur permettre de trouver une place sur et hors voirie. Nous leur permettons également de payer leur stationnement directement depuis l’application (avec, pour la première fois en France, Paypal et Apple Pay comme moyens de paiement).

À côté de cela, nous proposons une solution de cartographie/géomatique permettant de numériser tous les emplacements voirie d’une ville (avec typologie des emplacements et prix), et de visualiser sur un outil en SaaS toutes les informations pertinentes pour une ville afin d’établir une politique d’urbanisme efficace (taux de rotation des places, recettes par place...). 

Enfin, nous avons développé un algorithme de NLP (Natural Language Processing) permettant de lire automatiquement les arrêtés municipaux neutralisant des places de stationnement (travaux, événements…), avec une mise à jour automatique des cartes pour faire figurer cette information.

**Vous avez engagé un groupe de travail sur la normalisation des données sur le stationnement en voirie. Quel est l’enjeu selon vous et quels retours avez-vous eus des réutilisateurs et producteurs de données ?**

L'absence d'une méthode standardisée de répertoriage des emprises de stationnements constitue un obstacle pour les villes et territoires de demain. Elle empêche un partage des données entre les acteurs publics et privés pour créer les solutions mobilités du futur. Nous en avons discuté avec transport.data.gouv.fr et Etalab et leur avons proposé de mettre notre schéma de données en open source. Macaron a créé ce standard afin d’en faire la première brique d’un écosystème de mobilité innovant. Nous l’avons présenté à des réutilisateurs de référence comme la RATP, la SNCF et Tom Tom, et à la Ville de Paris côté producteur. Leurs avis nous ont été précieux et utiles pour améliorer le schéma. Notamment sur la façon de représenter le nombre de places, sur son adaptation à d’autres pays et sur certaines régulations tarifaires. Notre ambition est que la publication de ce schéma facilite l’ouverture des données publiques, un vrai enjeu pour les villes et collectivités. La prochaine étape est la multiplication des publications de données ouvertes sur le stationnement voirie dans ce format « machine readable ». Elles nourriront les applications et algorithmes de milliers de startups et acteurs privés/publics. Macaron va participer à cet effort de publication puisque nous sommes en mesure de produire ces données.

![](/images/capture-d’écran-2021-10-08-à-16.14.31.png)

**Comment les villes et collectivités perçoivent et approchent ces enjeux d’ouverture des données de stationnement sur voirie?**

La plupart des villes et collectivités ont une connaissance partielle de la façon dont leurs emprises de stationnement sont utilisées, voire de leurs nombres et leur typologie. La connaissance y est souvent fragmentée entre plusieurs départements, et les mises à jour difficiles. Les données (quand elles existent) sont répertoriées dans des formats difficilement exploitables (documents PDF, voire papier…).
Hors, dans un contexte où l’e-commerce explose, où les entreprises de livraisons sur sollicitent la voirie, où des solutions de mobilité douces sont appelées à y prendre places (trottinettes et vélos partagés, VTC, bornes de recharge électrique…), il est vital pour les villes et collectivités d’avoir une maîtrise parfaite de leur voirie, d’en connaître l’usage et les potentialités, d’en évaluer la rentabilité. Il faut coder la voirie. En numériser chaque recoin et ouvrir ces données aux startups et entreprises privées qui constitueront un vivier de solutions pour la ville de demain. C’est le sens de la loi Lemaire et de la LOM (Loi d’Orientation des Mobilités) qui font de l’open data un impératif pour les villes. Macaron collabore avec elles pour coder leurs territoires. Pour les connecter au futur. Et leur permettre de relever les défis excitants de demain.