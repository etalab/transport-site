# Guide de publication des données statiques de transport collectif (lignes régulières)

Ce guide s’adresse spécifiquement aux personnes souhaitant publier leurs données théoriques de transport collectif (points d’arrêts, lignes, tracés, tarifs, accessibilité et horaires théoriques).

Au fur et à mesure de l’élargissement du Point d’Accès National vers le temps réel et les autres données de transport, d’autres guides seront publiés.

## Étape 1 : Générer le jeu de données au format GTFS

Deux **formats** principaux existent pour décrire des réseaux de transports publics :

* **[NeTEx](http://netex-cen.eu/)** : norme européenne visant l’interopérabilité des données entre États membres ;
* **[GTFS](https://developers.google.com/transit/gtfs/)** : standard le plus utilisé par les services de mobilité d’information voyageur multimodale. Il est moins riche, mais plus normé que le NeTEx et plus simple à utiliser (plus d’outils compatible et plus simple de développer ses propres outils).

Pour l’instant, **la plateforme transport.data.gouv.fr accepte des fichiers au format GTFS** : c’est le format qui permettra aux usagers de votre territoire de bénéficier de services de mobilité innovants au plus vite.

Dans la plupart des cas, **le fichier GTFS décrivant votre réseau de transport public existe déjà** : c’est en effet le standard classique utilisé par les services d’information voyageur (Système d’Information Multimodal (SIM), applications de mobilité, projet de recherche, etc.). Ce fichier GTFS est généralement généré par l’exploitant transport, à l’aide d’un Système d’aide à l’exploitation et à l’information voyageur (SAEIV). En cas de difficulté pour générer un fichier GTFS, n’hésitez pas à contacter [contact@transport.beta.gouv.fr](mailto:contact@transport.beta.gouv.fr).


À moyen-terme, **la plateforme transport.data.gouv.fr proposera des outils de conversion de fichiers GTFS vers la norme NeTEx** afin de vous aider à vous conformer à la réglementation.

## Étape 2 : Accepter les conditions d’utilisation de la plateforme
Chaque jeu de donnée mis à disposition du public sous une licence de réutilisation qui spécifie les droits et devoirs des réutilisateurs lorsque ceux-ci téléchargent les fichiers en question, sans besoin d’identification.


Le Point d’Accès National encourage l’utilisation de licences largement utilisées pour permettre la réutilisation la plus large possible des données et accélérer le déploiement de services de mobilité innovants facilitant les déplacements des usagers.

En particulier, il est demandé aux producteurs de données de s’aligner sur l’harmonisation juridique (conditions d’utilisation) proposée sur la plateforme.


*La réutilisation des informations disponibles sur transport.data.gouv.fr est soumise à la licence ODbL. Il est précisé que la clause de partage à l’identique figurant à l’article 4.4 concerne les informations de même nature, de même granularité, de même conditions temporelles et de même emprise géographique.*

Cette harmonisation juridique présente trois avantages :

* Une **explicitation de la licence ODbL** adaptée aux transports qui lève les freins à la réutilisation des données et au déploiement de services de mobilité dans les territoires ;
* Une **sécurité juridique** pour les producteurs (garantie de conformité avec les licences autorisées par le [règlement européen 2017/1926](https://eur-lex.europa.eu/legal-content/FR/TXT/HTML/?uri=CELEX:32017R1926&from=EN)) comme pour les réutilisateurs (explicitation des cas d’obligation de partage à l’identique) ;
* Une **logique de commun numérique** : le réutilisateur participera à la mise en qualité de votre fichier GTFS, en reversant sur le Point d’Accès National l’ensemble des modifications, améliorations et corrections effectuées sur la base de données initiale.

## Étape 3 : Identifier un référent pertinent, responsable de la publication du jeu de données, de sa mise à jour et de sa correction

Il est essentiel que pour chaque jeu de données publié, un point de contact soit clairement identifié. Cette personne pourra notamment :

* créer un compte personnel sur [data.gouv.fr](https://data.gouv.fr) pour publier le jeu de données ;
* mettre à jour le jeu de données lorsque c’est nécessaire ;
* répondre aux questions des réutilisateurs sur les données et sur le réseau grâce au module de discussion de la plateforme ;
* s’assurer de l’amélioration de la qualité du fichier au fil de l’eau, en utilisant notamment les outils proposés sur le Point d’Accès National (module de validation).

## Étape 4 : Référencer le jeu de données sur le Point d’Accès National

Le référencement du jeu de données au format GTFS sur le Point d’Accès National est possible dès lors qu’une fiche a été publiée par le producteur de données sur la plateforme nationale data.gouv.fr. (Le Point d'Accès National référence par ailleurs l'ensemble des jeux de données au format GTFS ouverts en licence ouverte (Etalab) ; si l'autorité organisatrice ou l'exploitant créent un compte sur data.gouv.fr pour publier le fichier en son nom, le Point d'Accès National retirera cette fiche.)

Pour une explication pas à pas de l’utilisation de la plateforme data.gouv.fr, se référer au [guide détaillé](http://www.opendatalab.fr/images/doc/Tuto_chargement_donnees_Opendata_v2.pdf) publié par le SGAR Occitanie.

* Créez un compte personnel sur data.gouv.fr ;
* Créez un profil _organisation_ au nom de votre structure (exemple : « Métropole Européenne de Lille ») ou demandez à rejoindre l’organisation relative à votre structure si elle existe déjà ;
* Est-ce que vous avez une **plateforme de données ouvertes locale** (tel que OpenDataSoft ou CKAN) ?
    * **Oui :** Configurez le moissonneur de data.gouv.fr qui référencera tous les jeux de données de votre plateforme locale et qui mettra à jour les métadonnées toutes les nuits.
    * **Non :** Créez une fiche sur data.gouv.fr pour publier le jeu de données GTFS au nom de votre organisation. Vous pouvez soit héberger le jeu de données en le téléchargeant sur la plateforme (auquel cas il faudra le mettre à jour manuellement), soit spécifier l’adresse (URL) permanente où est hébergé le fichier.

Quelques points à retenir :

* Titre du fichier : spécifiez le nom du réseau de transport et son agglomération,
* Mot clé : spécifiez « GTFS »,
* Description : décrivez les spécificités du réseau et du fichier publié pour aider les réutilisateurs à faire bon usage de votre jeu de données,
* Licence : nos recommandations sont la Licence **[ODbL](https://opendatacommons.org/licenses/odbl/summary/)** ou la **[Licence Ouverte Etalab](https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf)**. Les fichiers publiés sous Licence Ouverte — plus permissive — seront référencés sous Licence ODbL + conditions d’utilisation sur le Point d’Accès National, selon le principe du « qui peut le plus peut le moins ».
