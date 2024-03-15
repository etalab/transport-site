1. faire une branche, mettre à jour tool versions
2. Voir ce qu’il y a dans tool versions => doc sur où sont les versions disponibles, plus deprecations elixir.
3. Soit bump mineur, soit bump majeur.
4. Gaffe à OTP 26 => issue. 
5. Allez aussi chercher Erlang compatible
6. Plus Nodejs si possible, mais mieux vaut le faire après.
7. => Le mieux est une image qui bumbe tout, mais dans ma branche y aller par étapes.
8. Vérifier que les tests passent. Le build test va pas passer, c’est normal. Il est possible qu’il y ait des warnings à traiter. Traiter les warnings. Astuce : mix test | tee upgrade.log  
9. Possible de créer un ticket, voir https://github.com/etalab/transport-site/issues/3307
10. On peut faire la MAJ Elixir et pas OTP 26 https://github.com/etalab/transport-site/issues/3315
11. Si c’est tout smooth et que ça marche bien, cloner transport-ops en local. Voir https://github.com/etalab/transport-ops
12. Github workflow du repository : aller voir les tests pour protéger 
13. Donc : une fois branche en local qui marche bien, modifier transport-ops pour faire correspondre, vérifier que tout marche bien, puis faire une release (avec le nom bien formaté).
14. Puis enfin, PR de transport-site à mettre à jour avec l’image.
15. Ne pas tester en local transport-site avec l’image docker : les tests sufiront + prochainement. Il n’y a pas de grosse diff entre passage asdf et docker.
16. Mettre à jour les readme :) => créer une doc sur trnasport-site sur le workflow.
