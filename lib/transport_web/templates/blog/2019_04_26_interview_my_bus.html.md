Nous réalisons une série d’entretiens avec différents réutilisateurs des données mises à disposition sur le Point d’Accès National, afin de valoriser l’usage qui est fait de la donnée de transport et illustrer des différents cas d'usage qu'elle peut avoir. 




# **Entretien avec Frédéric Pacotte, Co-Fondateur et CEO de MyBus**

### *(entretien intégral)*



MyBus est une application mobile complète à destination des usagers des transports en commun : guide horaire, temps réel, calcul d’itinéraire, partages communautaires et m-Ticket (titre de transport dématérialisé compatible avec 100% des smartphones). En agrégeant des informations multimodales comme les vélos en libre service et les parkings de co-voiturage, MyBus offre un service de MaaS (Mobility as a Service) concentrant toute l'offre de mobilité d'un territoire dans une seule plateforme. 

Qu'est ce qui fait la particularité du service offert par MyBus ? Dès le début, MyBus a fait le choix de ne pas se focaliser sur les réseaux urbains des grandes métropoles. Leur plateforme de services a été imaginée pour pouvoir aussi apporter des solutions à des réseaux de taille intermédiaire, notamment en matière de billettique légère.

![photo equipe mybus](/blog/Photo-equipe-TECH.png) 

Monkey Factory qui développe et déploie MyBus est auvergnate. Le siège social et l’équipe tech sont basés au Puy-en-Velay, l’équipe commerciale est basée à Clermont-Ferrand, au sein l’accélérateur de start-up Le Bivouac. Les équipes regroupent au total 17 « monkeys ».


### *A quoi vous servent les données mises à disposition en Open Data sur la plateforme transport.data.gouv.fr ?*

Ces données ouvertes, respectant un format standardisé, nous permettent d'ajouter rapidement de nouveaux réseaux à notre application mobile et notre plateforme Web. Ensuite, la mise à jour peut-être automatisée pour ainsi garantir une information de qualité à nos utilisateurs, qui sont aussi les usagers de ces mêmes AOMs et collectivités. Cette ouverture a permis à MyBus de devenir la solution d’info voyageur qui couvre le plus grand nombre de réseaux de transport en France (+ de 150), et cela devant les acteurs internationaux du secteur. 

Nous récupérons les jeux de données au format GTFS puisque c'est le format avec lequel nous travaillons nativement depuis 3 ans et qu'il s'est depuis imposé comme le format le plus utilisé. Nous faisons tout d'abord un travail de contrôle de ces données. Il nous arrive de les compléter, de les corriger : couleurs et ordres des lignes, ajustement des périodes, génération des tracés pour les cartes géographiques par exemple. C'est ensuite un fichier GTFS contrôlé, et éventuellement amélioré, que nous intégrons à MyBus. Nous remarquons que ces jeux de données sont de plus en plus qualitatifs, c'est très encourageant pour votre plateforme, et plus globalement pour la facilitation du quotidien des usagers des transports en commun.
### *Quelles sont les difficultés techniques que vous pouvez rencontrer en travaillant avec des données en open data/des données transport ?*

La difficulté majeure que nous rencontrons est la mise à jour de ces données par leurs producteurs. Il y a souvent une bonne impulsion initiale qui aboutit à la publication d'un premier jeu de données. Nous constatons parfois une publication postérieure à la date de début de validité du nouveau jeux de données. Cela conduit à fournir des informations inexactes, ou une absence ponctuelle d'information pour les usagers. Nous sommes conscients qu'il s'agit d'un travail parfois lourd pour les producteurs de données. Nous sommes d’ailleurs prêts à prendre notre part de travail dans cette collaboration producteurs/réutilisateurs si nécessaire.

### *Cela vous arrive-t-il de collaborer de manière étroite avec une collectivité ou une AOM ? Qu’est ce que votre service peut offrir à une collectivité ?*

Toutes les données que nous intégrons à MyBus ne sont pas issues de l'open-data. Nous avons construit nous-mêmes un certain nombre des jeux de données que nous utilisons. Nous avons donc développé par la force des choses une expertise dans la production des données descriptives d'un réseau de transport. Certaines collectivités et AOMs nous ont demandé de les accompagner dans cette démarche comme par exemple le Bassin d'Arcachon ou Clermont-Ferrand.

D'autre part, pour les réseaux qui n'en disposent pas ou qui souhaitent renouveler leurs dispositifs numériques vieillissants, nous proposons une boite à outils complète qui comprend notamment une application mobile personnalisée et éditée en leur nom, un back-office de type SAEIV (Système d'Aide à l'Exploitation et d'Information des Voyageurs) ou un portail Web transport aux couleurs du réseau.

Enfin, la mise à disposition sur un réseau de transport de titres dématérialisés, le m-Ticket MyBus, passe systématiquement par la mise en œuvre d'un accord de distribution avec l'AOM ou l'exploitant. Nous sommes un dépositaire d'un nouveau genre. Nous travaillons ensuite main dans la main sur l'animation commerciale : incentive, promotion, parrainage, street marketing, réseaux sociaux. Notre modèle économique étant un modèle à la performance, à savoir un commissionnement sur les ventes, nous partageons un objectif commun avec notre client, la collaboration est donc au cœur de notre mode de fonctionnement.

### *Selon vous, quelle est la plus grande valeur ajoutée de votre offre de service pour les usagers finaux ?*

La surface de notre audience et les interactions régulières avec notre support utilisateur nous permettent d'avoir un recul intéressant sur les attentes des usagers des transports en commun. La plupart réclame une simplification au quotidien de l'expérience de mobilité. Cela passe par 2 facteurs essentiels :

- **L'information temps réel ;** on accepte plus volontiers d'attendre si l'on sait combien de temps. Une large diffusion des informations d'avance/retard et des perturbations rend les transports en commun moins anxiogènes. MyBus met largement en avant ces informations quand elles existent (et fournit parfois des solutions légères de production du temps réel). Le temps réel est d'ailleurs la prochaine étape dans la dynamique d'ouverture et de partage des données de mobilité.
- **L'accès simplifié aux titres de transport,** aujourd'hui le média le plus largement partagé par les usagers est le smartphone. Il y a peu de chance que nous oublions notre smartphone à la maison ou au travail et nous nous organisons de mieux en mieux pour ne pas tomber en panne de batterie. C'est aussi une excellente option pour les utilisateurs occasionnels qui ne savent pas où et comment acquérir un titre de transport.

![capture ecran temps réel](/blog/Temps-Reel.png) 

###  *Quels sont les développements futurs que vous envisagez pour MyBus ?*


Les prochaines évolutions à court terme de notre offre de services sont les suivantes : 
-  **L'interopérabilité,** un trajet est souvent la combinaison de plusieurs réseaux, comme par exemple un transport interurbain + un transport urbain. L'utilisateur doit dans bien des cas gérer séparément l'acquisition et la validation de son titre de transport dématérialisé, quand il existe. MyBus multipliant les accords de distribution, notre approche transversale nous permet de proposer des solutions d'interopérabilités avec beaucoup plus d'agilité. 
- **Le paiement à l'usage,** la digitalisation de l'ensemble du parcours de l'usager facilite la mise en œuvre d'une tarification intelligente basée sur le type de mobilité de chacun. Nous sommes capables d'ajuster la tarification en pré ou post paiement en respectant la gamme tarifaire en place. 
- **L'intelligence collective,** les fonctionnalités de partage communautaire permettent de rendre les usagers acteurs de leur réseau  en informant les autres usagers des conditions de déplacement  (avance/retard, places assises, saturation) ou l’exploitant lui-même (dégradations, erreurs, suggestions…). 
- **La multimodalité,** les déplacements quotidiens permettent de combiner mobilités douces et transports traditionnels fournissant ainsi une réelle alternative aux déplacements traditionnels et notamment en voiture. Nous intégrons déjà sur certains réseaux les vélos en libre service avec le statut des stations en temps réel et nous avons ajouté récemment les parkings de co-voiturage. C'est le cas de Rennes et Avignon par exemple.

![capture ecran multimodalite](/blog/Multimodalite-Mockup.png) 

###  * Quelle place devrait être accordée à l'open data dans le développement de nouvelles politiques de mobilité ?  *

Nous pensons que la digitalisation du parcours de l'usager est l'une des clés du développement des transports en commun. De ce point de vue, la mobilité urbaine et péri-urbaine est en retard. Face à l'immense défi qui se présente à nous dans ce domaine, il est important de créer les conditions favorables à l'émergence de nouveaux services, de nouveaux produits. L'open-data est le terreau fertile dans lequel vont pousser les idées, beaucoup d'idées, des bonnes comme des mauvaises. Chez MyBus, nous sommes convaincus que ce sont les bonnes qui vont recueillir l'adoption des usagers et établir ainsi les bases de ces nouveaux usages. Pour les collectivités et les AOMs, l'enjeu ne réside pas dans la maîtrise de l'usage, mais dans la qualité et la complétude de l'information distribuée aux usagers.  

![capture ecran intelligence collective](/blog/communautaire.png) 
