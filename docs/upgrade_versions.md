## Gestion des versions et des images Docker

Le setup standard de développement s’appuie sur ASDF pour la gestion des versions. Cependant, la CI/CD (CircleCI) et la production s’appuient sur Docker.

Une première image Docker est mise à disposition par le dépôt tranport-ops : elle récupère une image Docker standard sur le hub Docker avec déjà la bonne version de Elixir et Erlang, rajoute Node et les outils annexes (transport-tools), et est publiée sur le dépôt d’images Docker de Github.

L’application transport-site récupère l’image Docker de transport-ops, et y rajoute uniquement son propre code, le compile, lance le serveur, les migrations, et expose le serveur à l’extérieur.

CircleCI pour les tests va donc faire ces étapes là de compilation du code Elixir, mais sans devoir reconstruire toute l’image (puisque s’appuyant sur l’image de transport-ops). Quand on pousse sur les serveurs de Clever Cloud, un premier serveur va créer l’image Docker finale (mêmes étapes que sur CircleCI, donc un temps de compilation existe) puis déployer l’image résultante sur un autre serveur. Potentiellement, on pourrait réduire à l’avenir le temps de déploiement en fournissant directement l’image Docker avec l’application précompilée, et que la même image serve pour les tests et pour la production.

## Processus de mise à jour

Les versions de ASDF et de Docker doivent être mises à jour dans la même branche de transport-site (sinon des tests ratent). Il faut donc en préalable du merge de la branche qu’une image Docker avec les bonnes versions de Elixir, Erlang/OTP et Node et les outils transport existe, donc qu’une branche correspondante sur transport-ops ait été mergée et un package crée. 

Dans les grandes lignes : on teste d’abord avec ASDF que tout va bien, puis on fait le nécessaire sur le repo transport-ops pour créer un package, et on finalise la branche sur transport-site avec la référence de l’image.

1. Créer une branche
2. Mettre à jour `.tool_versions`. Le fichier contient un peu de documentation sur les commandes ASDF, et où trouver les versions disponibles, la compatibilité Elixir/Erlang et les notes de versions.
3. Vérifier que :
    1. Ça compile
    2. Les tests passent (il y aura forcément une erreur liée à la différence de version avec Docker)
    3. Credo et Dialyxir n’aient pas de warning.
4. Noter tous les warnings, qui serviront soit dans une issue pour un traitement postérieur, soit seront mis dans la pull request. Exemple : https://github.com/etalab/transport-site/issues/3307
5. Créer un package Docker correspondant dans le dépôt https://github.com/etalab/transport-ops On peut pousser sur une branche pour faire tourner la CI Github Workflow, pas besoin d’avoir Docker en local. Lire le README de transport-ops pour le détail.
6. Modifier transport-site avec la bonne image Docker. Il n’est pas nécessaire de tester en local transport-site avec l’image Docker : les tests sufiront + prochainement. Il n’y a pas de grosse diff entre passage asdf et docker.
7. Créer une pull request en draft pour faire tourner Circle CI.
8. Tester le plus possible : en local et sur le serveur de staging (`git push origin ma_branche:prochainement`)
