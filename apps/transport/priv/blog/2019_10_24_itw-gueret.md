# Interview Guéret

*Afin d’améliorer l’information voyageur et la fréquentation des transports en commun en France, notamment au travers des technologies du numérique, transport.data.gouv.fr vise à documenter les bonnes pratiques autour de l’ouverture des données de transport. Des données ouvertes sont des données mises à disposition de tous, pour une réutilisation libre, en ayant pour but l’émergence de services numériques innovants d’accompagnement à la mobilité.*

La plateforme transport.data.gouv.fr privilégie le référencement de données au format GTFS (General Transit Feed Specifications). Il s’agit d’un format de fichier commun pour les horaires de transports en commun. Le fichier GTFS combine des informations géographiques ainsi que des données horaires, décrivant les trajets effectués, les arrêts géolocalisés, et les horaires de passage aux différents arrêts.
Aujourd’hui, la majorité des logiciels de gestion de flotte de bus ou de SAEIV (Système d'Aide à l'Exploitation et l'Information Voyageur) permettent de créer automatiquement un export du fichier GTFS. Lorsqu’une gestionnaire de réseau ne dispose pas de ce type d’outil, il est possible de produire un fichier GTFS manuellement, comme en témoigne le retour d’expérience de la Communauté d’Agglomération du Grand Guéret (23).

## Comment créer un fichier GTFS à partir de rien?
**Témoignage  du chargé de mission plan climat / mobilité à la Communauté d’Agglomération du Grand Guéret**

*« Notre but est qu’il y ait plus de gens dans les bus et moins dans les voitures. »*

La Communauté d’Agglomération du Grand Guéret, dans le département de la Creuse, a une population de 30 000 habitants. Elle dispose d’un réseau de transport urbain âgé de 5 ans et opère 7 lignes urbaines dans Guéret (la ville centre,13 000 habitants).
Ne disposant pas de données de transport au format GTFS, il a été nécessaire de créer ce fichier manuellement..

### Pourquoi a-t-il été important pour vous d’ouvrir vos données de transport au format GTFS?

Tout d’abord, nous avons agi dans une volonté de respecter nos obligations règlementaires [en terme d’ouverture de données, NDLR], mais surtout dans une optique d’augmenter la fréquentation des bus en rendant l’accès à l’information plus facile pour les voyageurs.

Avant, il n’existait que trois canaux d’accès à l’information : soit en consultant les horaires affichés aux arrêts de bus ; soit en consultant les fiches horaires (en les téléchargeant sur internet ou en les consultant sur papier) ; soit en se rendant à l’espace mobilité dans la gare pour poser ses questions. L’ouverture des données de transport permettra prochainement aux usagers du réseau de bus d'accéder à ces informations par un canal supplémentaire : directement sur smartphone ou ordinateur grâce à une application comme MyBus ou via Google Maps. Ces outils permettent de calculer un itinéraire automatiquement et de gérer les correspondances entre différentes lignes. Actuellement, si une personne veut faire un itinéraire qui nécessite un changement, elle doit prendre les deux fiches horaires côte à côte pour déterminer à quel moment faire la correspondance, ce qui peut être un frein pour certaines personnes.

Une grande partie des utilisateurs du réseau de bus sont des collégiens et des lycéens. Internet ne pose aucune difficulté pour eux. Rendre les informations disponibles par internet et les différents canaux numériques nous semble intéressant.

Quant au choix de l’opendata, il est plus simple pour nous d’ouvrir nos données en opendata que d’effectuer une démarche pour chaque opérateur. Les données ouvertes pourront directement être reprises par différents services (MyBus, Google Maps, Mappy, TransportR, Navitiat etc.). De plus, cela garantit le libre accès de tous les opérateurs à ces données. A priori, la LOM se dirige de plus vers une ouverture obligatoire des données de transport.

### Vous avez construit vous-même le fichier GTFS pour le Grand Guéret à partir de rien. Pouvez-vous nous expliquer les étapes que vous avez suivies pour réaliser ce travail?

La première chose que nous avons faite a été de **saisir la localisation des arrêts de bus** et le tracé des lignes de transport en commun dans **OpenStreetMap (OSM)**, grâce à un outil qui s’appelle **JOSM (Java OpenStreetMap)**. Ça a été facile dans le cas de Guéret, parce que le réseau compte 7 lignes de bus. Quand on connaît bien le tracé d'une ligne, il y en a pour une heure de travail pour la création des arrêts, le repérage du tracé exact, tout en faisant quelques modifications sur la topographie d’OSM pour mettre à jour et documenter cela.

La deuxième étape a été de structurer nos données horaires, en vue de construire un fichier GTFS (qui combine à la fois des données topographiques et des données d'horaires). Pour rappel, sur OSM on ne retrouve que des informations topographiques (donc pas d'horaires de passage pour les bus).

Pour **produire un fichier GTFS**, nous nous sommes servis du logiciel libre **Static GTFS Manager**. Il nous a permis d'exporter un premier fichier au format GTFS avec juste la structure des fichiers qui le composent.  Cela a pris environ une demi-journée de travail. Ensuite, nous avons utilisé le tableur de **Libre Office**, pour **renseigner les horaires de passage**, dont nous disposions déjà. Comme nous avions déjà saisi sur **OpenStreetMap** tous les arrêts de bus et les tracés de toutes les lignes, nous avons facilement exporté les coordonnées des arrêts de bus, grâce à un **logiciel de SIG** (QGIS en l'occurrence avec le plugin OverPass Turbo).  Il nous a ensuite suffit de faire un copier-coller des coordonnées pour les saisir dans le GTFS.

Après avoir créé le fichier GTFS, nous avons eu recours à plusieurs **« validateurs »** pour **contrôler d'éventuelles erreurs de saisie**. [*Ce sont des outils permettant de vérifier la cohérence des données saisies dans le GTFS, et de contrôler le fichier pour repérer d'éventuelles erreurs, NDLR*] .Nous avons utilisé le validateur de Transit Screen, le validateur proposé par transport.data.gouv.fr ainsi que celui de Google Transit. En corrigeant les erreurs signalées une par une, nous avons réussi à obtenir un fichier GTFS de qualité.

L’étape la plus compliquée et la plus longue, a été la **production du fichier shapes.txt** dans le GTFS. Ce fichier décrit le trajet effectué par chaque ligne de bus. Ce shapes.txt est juste un outil de rendu visuel qui n’est jamais utilisé pour calculer quoique ce soit. Il s’agit d’un fichier qui reprend les coordonnées de chaque point de passage du bus, et les ordonne. Ces données ne sont pas directement exportables depuis OSM. Il est possible de reprendre les coordonnées de chaque point d’arrêt depuis OSM, mais le fait de les ordonner est compliqué. Nous n’avons pas trouvé de moyen automatique de le faire, et au final pour 7 lignes de bus, nous avons eu plus vite fait de le faire à la main. Nous avons redessiné le tracé des lignes de bus directement dans **QGIS**, en mettant des points de passage pour que la forme globale soit bonne. 200 points par ligne permettent d’avoir un bon rendu visuel. Cela nous a pris 2 heures pour les 7 lignes.

En somme, pour construire un fichier GTFS à partir de rien, un technicien qui est habitué à utiliser soit des outils de SIG ou OpenStreetMap peut compter à peu près une semaine et demie de travail, de manière discontinue.

