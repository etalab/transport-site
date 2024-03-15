## Gestion des versions et des images Docker

Le setup standard de développement s’appuie sur ASDF pour la gestion des versions. Cependant, la CI/CD (CircleCI) et la production s’appuient sur Docker.

Une première image Docker est mise à disposition par le dépôt tranport-ops : elle récupère une image Docker standard sur le hub Docker avec déjà la bonne version de Elixir et Erlang, rajoute Node et les outils annexes (transport-tools), et est publiée sur le dépôt d’images Docker de Github.

L’application transport-site récupère l’image Docker de transport-ops, et y rajoute uniquement son propre code, le compile, lance le serveur, les migrations, et expose le serveur à l’extérieur.

CircleCI pour les tests va donc faire ces étapes là de compilation du code Elixir, mais sans devoir reconstruire toute l’image (puisque s’appuyant sur l’image de transport-ops). Quand on pousse sur les serveurs de CleverCloud, un premier serveur va créer l’image Docker finale (mêmes étapes que sur CircleCI, donc un temps de compilation existe) puis déployer l’image résultante. Potentiellement, on pourrait réduire à l’avenir le temps de déploiement en fournissant directement l’image Docker avec l’application précompilée, et que la même image serve pour les tests et pour la production.

## Processus de mise à jour

Les versions de ASDF et de Docker doivent être mises à jour dans la même branche de transport-site (sinon des tests ratent). Il faut donc en préalable du merge de la branche qu’une image avec les bonnes versions de Elixir, Erlang/OTP et Node et les outils transport soit déjà présente, donc qu’une branche correspondante sur transport-ops ait été mergée et un package crée. 

Dans les grandes lignes : on teste d’abord avec ASDF que tout va bien, puis on fait le nécessaire sur le repo transport-ops pour créer un package, et on finalise la branche sur transport-site avec la référence de l’image.

1. faire une branche, mettre à jour tool versions
2. Voir ce qu’il y a dans tool versions => doc sur où sont les versions disponibles, plus deprecations elixir.
3. Soit bump mineur, soit bump majeur.
4. Gaffe à OTP 26 => issue. 
5. Allez aussi chercher Erlang compatible
6. Plus Nodejs si possible, mais mieux vaut le faire après. Prendre la version LTS sur nodejs.org
7. => Le mieux est une image qui bumbe tout, mais dans ma branche y aller par étapes.
8. Vérifier que les tests passent. Le build test va pas passer, c’est normal. Il est possible qu’il y ait des warnings à traiter. Traiter les warnings. Astuce : mix test | tee upgrade.log  
9. Possible de créer un ticket, voir https://github.com/etalab/transport-site/issues/3307
10. On peut faire la MAJ Elixir et pas OTP 26 https://github.com/etalab/transport-site/issues/3315
11. Si c’est tout smooth et que ça marche bien, cloner transport-ops en local. Voir https://github.com/etalab/transport-ops
12. Github workflow du repository : aller voir les tests pour protéger 
13. Donc : une fois branche en local qui marche bien, modifier transport-ops pour faire correspondre, vérifier que tout marche bien, puis faire une release (avec le nom bien formaté). Pour faire une release, voir le readme.
14. Puis enfin, PR de transport-site à mettre à jour avec l’image.
15. Ne pas tester en local transport-site avec l’image docker : les tests sufiront + prochainement. Il n’y a pas de grosse diff entre passage asdf et docker.
16. Mettre à jour les readme :) => créer une doc sur trnasport-site sur le workflow.
