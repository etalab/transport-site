Bonjour,

Vous avez un compte utilisateur associé à l‘adresse email **<%= @contact_email %>** sur
[transport.data.gouv.fr](https://transport.data.gouv.fr).

Nous n‘avons pas détecté d‘activité de votre part depuis plus de 12 mois.
<%= @horizon %> nous supprimerons votre compte conformément aux règles en vigueur
concernant les données utilisateur.

Si vous avez souscrit à des notifications concernant des jeux de données, vous
n‘aviez en effet pas besoin de vous connecter.

Pour conserver votre compte, il vous suffira de <%= link_for_login() %>.

À bientôt,

L’équipe transport.data.gouv.fr
