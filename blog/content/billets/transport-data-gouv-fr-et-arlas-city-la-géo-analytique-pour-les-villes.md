---
title: "Interview avec Gisaïa sur arlas.city : la géo-analytique pour les villes"
date: 2022-05-04T14:26:21.207Z
tags:
  - réutilisation
description: >-
  Gisaïa est une jeune entreprise française émanant de l’écosystème Spatial
  Toulousain et Européen. Sa vocation première est de valoriser la donnée
  géospatiale à travers sa transformation, son enrichissement et son exploration
  par le plus grand nombre. 


  Gisaïa est réutilisateur des données du PAN. Nous leur avons posé quelques questions pour mieux comprendre ils réutilisent ces données.


  "Nous œuvrons à ce que les organisations et entreprises du monde entier puissent pleinement bénéficier de la valeur ajoutée nichée dans les données géospatiales et souvent inexploitées du fait de la complexité et de la volumétrie de cette dernière. 


  Dans cette perspective, nous avons créé la solution open source ARLAS. La solution allie technologies big data et géo-analytique pour offrir une toute nouvelle approche dans l’exploration et l’analyse de données référencées dans l’espace et dans le temps."
images:
  - /images/article-transport.data.gouv.jpg
---
**Transport.data.gouv.fr : Pouvez-vous nous parler d'ARLAS ?**

> **ARLAS** est aujourd’hui adoptée par des institutions telles que le CNES, Tisséo Collectivité (Toulouse) ou l’IRD, par de jeunes startups innovantes telles que Skyline Partners (UK) et enfin par de grands industriels tels que AIRBUS Defence & Space (ADS). 

![ARLAS pour l’exploration et la visualisation de millions d‘images satellite.](/images/article-transport.data.gouv1.jpg "ARLAS pour l’exploration et la visualisation de millions d‘images satellite.")

*ARLAS pour l’exploration et la visualisation de millions d‘images satellite.*

![ARLAS pour l’exploration et l'analyse de trajectoires d’oiseaux migrateurs.](/images/article-transport.data.gouv2.jpg "ARLAS pour l’exploration et l'analyse de trajectoires d’oiseaux migrateurs.")

*ARLAS pour l’exploration et l'analyse de trajectoires d’oiseaux migrateurs.*

**Transport.data.gouv.fr : Est-il possible de lier les villes, transport.data.gouv.fr et ARLAS pour enfait un trio gagnant ?**

> Un [rapport](https://ec.europa.eu/regional_policy/en/information/publications/reports/2020/report-on-the-quality-of-life-in-european-cities) de la Commission européenne publié en 2020 met en évidence la contribution majeure de la qualité des transports en commun dans l’épanouissement des habitants des villes. Les habitants s’épanouissent dans les villes où les transports publics sont efficaces et sûrs.

**Transport.data.gouv.fr : Et la mobilité dans tout ça ?**

> La mission première des Autorités Organisatrices des Mobilités (AOM) est précisément d’améliorer la mobilité des habitants. Le premier levier est de déporter au maximum les trajets réalisés en véhicules privés (VP) vers des déplacements en transports communs (TC). 

##### Améliorer la mobilité en déportant les trajets VP vers les TC et le vélo.

![Améliorer la mobilité en déportant les trajets VP vers les TC et le vélo.](/images/article-transport.data.gouv3.jpg "Améliorer la mobilité en déportant les trajets VP vers les TC et le vélo.")

> Mais pour cela, l’offre de transport se doit d’être attrayante auprès des habitants. Ce même rapport de la Commission européenne met en avant les principaux axes de satisfaction pour les usagers des transports. Les trois premiers sont :
>
> * La fréquence, en d’autres termes le temps qui s’écoule entre deux passages de véhicules de transport à un arrêt
> * La fiabilité, c’est à dire si les véhicules arrivent et partent à l’heure annoncée
> * L’accessibilité, c’est à dire le temps moyen pour une personne pour se rendre à un arrêt
>
> Puis viennent ensuite la sécurité et enfin le coût. En d’autres termes, les habitants sont heureux là où les transports sont performants, fiables et accessibles.

**Transport.data.gouv.fr : Que pouvez-vous nous dire sur les données GTFS ?**

> La normalisation des données décrivant les services de transport public, entre autres à travers le format GTFS, a été une formidable opportunité pour Gisaïa de transposer ARLAS pour offrir une perspective géo-analytique sur les performances des transports aux Autorités Organisatrices de la Mobilité (AOM). Cette solution spécialement déclinée pour les AOMs s’appelle **arlas.city**.
>
> La mission d’**arlas.city** est d’élaborer et de représenter les indicateurs mesurant ces axes de performance. Les responsables au sein des AOMs (chargés d’études, chargés de projets et responsables publics) sont ainsi appuyés dans leur prise de décisions par des indicateurs analytiques fiables.

##### arlas.city - Indicateur performance de l’offre de transport portant sur la fréquence et l’accessibilité des arrêts d’une ligne.

![arlas.city - Indicateur performance de l’offre de transport portant sur la fréquence et l’accessibilité des arrêts d’une ligne.](/images/article-transport.data.gouv4.jpg "arlas.city - Indicateur performance de l’offre de transport portant sur la fréquence et l’accessibilité des arrêts d’une ligne.")

> **arlas.city** permet de charger les données décrivant l’offre théorique (format GTFS) ainsi que tout autre silo de données portant sur le réseau et son emprise territoriale, tels que les données d’exploitation (validations,  retards) ou même les données de référencement de la population (carroyage INSEE). La donnée GTFS joue ici un rôle majeur: les autres silos de données viennent se projeter sur cette donnée de référence à travers la notion de “passage” (voir plus bas).

##### arlas.city - Calculs de performance des transports publics en termes d’accessibilité territoriale proposée aux usagers.

![arlas.city - Calculs de performance des transports publics en termes d’accessibilité territoriale proposée aux usagers.](/images/article-transport.data.gouv5.jpg "arlas.city - Calculs de performance des transports publics en termes d’accessibilité territoriale proposée aux usagers.")

**Transport.data.gouv.fr : vous nous disiez que le PAN était le hub de référence, pourquoi cela ?**

> Au vu de la sophistication des réseaux de transport, une approche décisionnelle basée sur la donnée (data driven decision making) est le moyen d’opérer des choix sûrs et justifiables auprès des parties prenantes. Cette approche permet également de mesurer les impacts des choix ou scénarios envisagés.
>
> Mais encore faut-il que la donnée (entre autres GTFS) soit disponible, référencée, accessible au téléchargement, exhaustive, cohérente, à jour et fiable. En effet, les analystes et décideurs abordent la donnée dans le processus décisionnel avec prudence, parfois avec méfiance, car leur crédibilité est mêlée à celle de la donnée : cette dernière doit gagner la confiance des décideurs.
>
> C’est précisément sur ces points que le hub de données **transport.data.gouv.fr** prend tout son sens. Le site référence la donnée et la rend téléchargeable. Des métadonnées permettent de qualifier l’archive et de facilement la retrouver sur l’interface ou par l’API proposée par le site.
>
> Sur chaque archive, une frise chronologique démontre la haute disponibilité des archives. La fiabilité de l’accès est primordial pour **arlas.city**.
>
> Un jeu d’étiquettes permet de rapidement identifier le profil des données contenues dans l’archive : position des arrêts, horaires, mode de transport couverts, etc. Ceci permet de connaître la complétude des données avant même de les télécharger.

![](/images/article-transport.data.gouv6.jpg)

> Aussi, une validation des données GTFS est appliquée par le site **transport.data.gouv.fr** et le résultat est restitué. Ainsi, il est possible d’évaluer la qualité de la donnée par un simple coup d'oeil sur les avertissements fournis par le validateur.

![](/images/article-transport.data.gouv7.jpg)

> Le site **transport.data.gouv.fr** met à disposition d’autres types de données.
> Il est ainsi possible de consommer les données GTFS-realtime pour connaître en temps réel la position des bus et leur retards. L’emplacement des stations de vélos et l’usage des vélos à travers le temps sont accessibles à travers le format GBFS, ce qui en facilite grandement l’exploitation.

**Transport.data.gouv.fr : Comment utilisez-vous les données du PAN ?**

> Pour commencer, la plateforme **arlas.city** permet aux utilisateurs de regrouper leurs archives de données. Les données peuvent porter sur l’offre théorique (GTFS),  sur l’offre réalisée, sur les données de billetique, sur la capacité des véhicules, ou sur tout autre thème qui peut être raccroché à l’offre théorique. 
>
> Un traitement parallélisé sur ces silos indépendants aligne la donnée en vue d’être unifiée. Cette donnée ainsi transformée couvre toutes les dimensions de la donnée source, de manière cohérente et sur un unique concept appelé “passage”, c'est-à-dire l’évènement qu’un véhicule d’une ligne donnée a effectué à un instant donné entre deux arrêts donnés. 
>
> L’utilisation de cette notion présente un intérêt majeur car c’est l’information qui a la granularité la plus fine. Il est alors possible d’y greffer tout type d’information. C’est le cas des données de validations (billettique), des données de retards, mais aussi des capacités de véhicules ou encore des vitesses mesurées entre arrêts. A noter que pour un réseau de métropole, il est possible de dénombrer jusqu’à cent millions de passages sur une année!
>
> La donnée préparée par **arlas.city** est dite “analytic-ready”. En d’autres termes, la donnée est sous une forme optimale pour être analysée instantanément sur tous ses axes. Cette capacité analytique instantanée sur des dizaines de millions de passages est précisément ce qu’offre la plateforme **arlas.city**.
>
> Les autorités organisatrices de la mobilité peuvent étudier chaque aspect de l’offre de transport. En premier lieu, les chargés d’études peuvent étudier l’offre théorique et les fréquences de passages proposées, comme illustré ci-dessous.

##### arlas.city - Visualisation sur la carte des vitesses de circulation des véhicules (tramway) et visualisation dans la frise temporelle de l’évolution de la fréquence de passage des véhicules sur le réseau Nantais.

![arlas.city - Visualisation sur la carte des vitesses de circulation des véhicules (tramway) et visualisation dans la frise temporelle de l’évolution de la fréquence de passage des véhicules sur le réseau Nantais.](/images/article-transport.data.gouv8.jpg "arlas.city - Visualisation sur la carte des vitesses de circulation des véhicules (tramway) et visualisation dans la frise temporelle de l’évolution de la fréquence de passage des véhicules sur le réseau Nantais.")

> Les vitesses prévues de circulation des véhicules ainsi que les vitesses réellement constatées pour effectuer les déplacements sont directement analysables et comparables. Les retards permettent d’identifier rapidement les points de frictions et éventuellement d’ajuster les vitesses commerciales et les tables horaires en conséquence.
>
> Une autre analyse riche en enseignements est la superposition de la structure du réseau de transport à la densité de la population. Ainsi, il est très simple d’identifier les populations mal desservies. 

##### arlas.city - Visualisation sur la carte de la structure du réseau qui se superpose à la densité de population pour identifier les zones habitées mal desservies. Ici sur la commune Villeneuve Tolosan, au sud de Toulouse.

![arlas.city - Visualisation sur la carte de la structure du réseau qui se superpose à la densité de population pour identifier les zones habitées mal desservies. Ici sur la commune Villeneuve Tolosan, au sud de Toulouse.](/images/article-transport.data.gouv9.jpg "arlas.city - Visualisation sur la carte de la structure du réseau qui se superpose à la densité de population pour identifier les zones habitées mal desservies. Ici sur la commune Villeneuve Tolosan, au sud de Toulouse.")

> La performance de mobilité offerte par le réseau est évaluée par les isochrones. En d’autres termes, le territoire accessible en un temps donné à partir d’un point de départ est calculé. Il est possible de calculer les isochrones dans différentes configurations pour évaluer le gain ou la perte d’accessibilité. Par exemple, les isochrones peuvent être calculés avec ou sans une ligne de tramway en cours d’étude et mesurer ainsi l’impact de l’ouverture de la ligne. Ou bien les isochrones peuvent être calculés sur des tranches horaires différentes, tel que présenté ci-dessous.

##### arlas.city - Visualisation sur la carte des isochrones au départ de la gare de Lille entre 6h30 et 8h du matin.

![arlas.city - Visualisation sur la carte des isochrones au départ de la gare de Lille entre 6h30 et 8h du matin.](/images/article-transport.data.gouv10.jpg "arlas.city - Visualisation sur la carte des isochrones au départ de la gare de Lille entre 6h30 et 8h du matin.")

##### arlas.city - Visualisation sur la carte des isochrones au départ de la gare de Lille entre 8h et 9h30 du matin.

![arlas.city - Visualisation sur la carte des isochrones au départ de la gare de Lille entre 8h et 9h30 du matin.](/images/article-transport.data.gouv11.jpg "arlas.city - Visualisation sur la carte des isochrones au départ de la gare de Lille entre 8h et 9h30 du matin.")

> Bien d’autres analyses sont possibles avec arlas.city. Elles peuvent porter sur la capacité des véhicules, sur les données de validation ou encore sur les données Origine/Destination. 
>
> Mais arlas.city n’a pas la prétention de fournir tous les indicateurs possibles et chaque communauté a ses propres axes d’analyse. C’est pourquoi la solution offre aux utilisateurs une interface graphique dédiée pour qu’ils puissent élaborer par eux mêmes leurs indicateurs d’intérêt.

**Transport.data.gouv.fr : Quelles sont vos ambitions pour la suite ?**

> La vocation de la solution arlas.city est d’accompagner les autorités organisatrices de la mobilité à mettre en place une stratégie décisionnelle basée sur la donnée pour l’optimisation de l’offre de transport. Nous avons vu leurs contributions:
>
> * les données GTFS permettent de mesurer les performances théoriques de l’offre et leur adéquation à la distribution spatiale de la population
> * les données de l’offre réalisée (ex: retards et annulations) permettent d’évaluer la performance opérationnelle
> * les données billetiques offrent une vue sur le niveau d’adoption du service par les usagers
>
> Tous ces axes permettent d’améliorer significativement l’offre de transport.
>
> arlas.city cherche de plus en plus à résoudre une difficulté que rencontrent les villes et qui est pour le moment mal adressée: l’offre de transport doit avant tout répondre à une demande de mobilité. En d’autres termes:
>
> * Les lignes de transports doivent être structurées en fonction des principaux flux de voyageurs pour éviter les changements de lignes. 
> * Les arrêts doivent être placés au plus proche des origines et des destinations. 
> * Les horaires doivent être adaptés à l’amplitude de la demande qui évolue au cours des heures, de la journée et des semaines.
>
> Ce besoin en mobilité est particulièrement difficile à appréhender. Différentes sources de données de mobilité des individus sont exploitées mais elles présentent toutes un inconvénient. Elles sont chères à acquérir pour les villes. Quand elles ne le sont pas, le manque de détails des données ne permet pas de prendre des décisions précises. Enfin, avec les bouleversements sociétaux rencontrés ces dernières années, il est primordial de manipuler des données récentes qui reflètent la demande actuelle.
>
> Gisaïa et de nombreuses entreprises pourraient capitaliser si les données étaient normalisées et facilement accessibles via une unique plateforme. Ainsi, les efforts se concentreront sur la valorisation des données et l'innovation et moins sur les problématiques spécifiques à chaque source de données.
>
> Les enquêtes Origine/Destination, les données de déplacements issues des télécommunications, les compteurs intelligents déployés dans les villes portent un potentiel qui doit être mis à la disposition des villes. 
>
> La solution ARLAS est prête pour faire resurgir des motifs de déplacements dans l’espace et dans le temps.

##### ARLAS - Visualisation de milliers de déplacements de navires en Mer du Nord.

![ARLAS - Visualisation de milliers de déplacements de navires en Mer du Nord.](/images/article-transport.data.gouv12.jpg "ARLAS - Visualisation de milliers de déplacements de navires en Mer du Nord.")

> La plateforme transport.data.gouv.fr , en complément des données déjà publiées, pourrait jouer un rôle majeur dans la normalisation, la fiabilisation et la mise à disposition de ces données de mobilité des individus. La valeur et l’apport sociétal de ses données en seraient décuplés. Les habitants des villes et métropoles en seraient les premiers bénéficiaires.

**Transport.data.gouv.fr : Comment peut-on vous retrouver pour plus d’informations ?**

> * Site web : [www.gisaia.com](http://www.gisaia.com)
> * Solution open source ARLAS: [arlas.io](http://arlas.io) et ses [démos](https://www.arlas.io/arlas-demo-io).
> * Solution cloud arlas.city: [arlas.city](http://arlas.city)
> * [Report](https://ec.europa.eu/regional_policy/en/information/publications/reports/2020/report-on-the-quality-of-life-in-european-cities) on the Quality of life in European cities

Merci pour vos partages et le temps consacré à cette interview ! A bientôt !