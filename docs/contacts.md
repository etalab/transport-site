# Contacts

Ce document décrit le fonctionnement des contacts dans notre application.

## Concepts métiers

Les contacts au sens de transport.data.gouv.fr sont des utilisateurs ou des listes de diffusion (`opendata@ma-collectivite.fr`).

Ces contacts sont créés :
- par le biais du backoffice par des membres de l'équipe du PAN
- automatiquement lors de la connexion au PAN par le biais de l'OAuth avec data.gouv.fr

Ainsi les contacts peuvent être des :
- producteurs : agents de collectivités, prestataires techniques assistant les collectivités ou entreprises, salariés d'entreprises de mobilité
- listes de diffusion : services SIG, open data et mobilité principalement
- réutilisateurs de données
- curieux

## Champs obligatoires

Les champs obligatoires sont des informations sur :
- l'identité (nom et prénom OU titre pour une liste de diffusion)
- adresse e-mail

## Lien entre contact et utilisateur data.gouv.fr

Un contact créé depuis le backoffice n'a pas de `datagouv_user_id`. Si la personne se connecte plus tard sur le PAN avec l'adresse e-mail associée au contact les comptes sont "liés" et on reprend le `datagouv_user_id`.

## Protection des données

L'adresse e-mail (`email`) et le numéro de téléphone (`phone_number`) sont stockés de manière chiffrée en base de données.

La colonne `email_hash` permet de retrouver un contact par son adresse e-mail.

## Cycle de vie

### Créations

- Un contact créé depuis le backoffice est géré par [`TransportWeb.Backoffice.ContactController`](https://github.com/etalab/transport-site/blob/master/apps/transport/lib/transport_web/controllers/backoffice/contact_controller.ex).
- La création d'un contact lors de la connexion est effectuée dans [`TransportWeb.SessionController`](https://github.com/etalab/transport-site/blob/4698271861462b72ea2eed4c310c301562ad3eee/apps/transport/lib/transport_web/controllers/session_controller.ex#L57). Ce controller est également en charge de sauvegarder un `datagouv_user_id` dans le cas où un contact est déjà existant (comparaison avec l'adresse e-mail).

### Mises à jour

- Un job ([`Transport.Jobs.UpdateContactsJob`](https://github.com/etalab/transport-site/blob/master/apps/transport/lib/jobs/update_contacts_job.ex)) est en charge de maintenir à jour les organisations associées à chaque contact pour lesquelles un `datagouv_user_id` est renseigné. Ce job est exécuté de manière quotidienne
- À chaque connexion sur le PAN ([une session dure 15 jours](https://github.com/etalab/transport-site/blob/4698271861462b72ea2eed4c310c301562ad3eee/apps/transport/lib/transport_web/endpoint.ex#L5-L12)), les informations de l'utilisateur data.gouv.fr sont synchronisées (prénom, nom, adresse e-mail). La dernière date de connexion est stockée dans `last_login_at`.

### Suppression

La seule possibilité de supprimer un contact est pour le moment par le biais du backoffice.

Un utilisateur ne peut pas supprimer son compte de manière autonome et un compte n'est pas supprimé en cas d'inactivité prolongée.

## Rôles de producteurs et de réutilisateurs

On ne qualifie pas le rôle d'un contact directement dans la table `contact`. En effet ce rôle (producteur ou réutilisateur) peut être mixte et est propre à un contexte ou un jeu de données.

Cette distinction est actuellement présente lors de l'abonnement aux notifications. Le contenu des notifications est adapté au rôle de l'utilisateur.

## Abonnements aux notifications

Un contact membre d'une organisation qui a un jeu de données sur le PAN pourra modifier des éléments de ce jeu de données sur son Espace Producteur et pourra s'abonner aux notifications en lien avec ce jeu de données en tant que producteur.

Un membre de l'équipe du PAN a la possibilité d'abonner des contacts à des notifications depuis le backoffice. Ceci est utilisé pour pouvoir abonner des contacts qui ne sont pas membres d'une organisation data.gouv.fr (prestataires techniques par exemple) mais qui ont un rôle de gestion d'un jeu de données. On considère que les abonnements aux notifications créés depuis le backoffice sont pour des contacts ayant un rôle de producteur et ceci est sauvegardé ainsi en base de données dans `notification_subscription.role`.

Si un contact était abonné en tant que réutilisateur à des notifications et qu'il devient membre de l'organisation produisant le jeu de données, son rôle sera mis à jour automatiquement par [`Transport.Jobs.NotificationSubscriptionProducerJob`](https://github.com/etalab/transport-site/blob/master/apps/transport/lib/jobs/notification_subscription_producer_job.ex), exécuté quotidiennement.
