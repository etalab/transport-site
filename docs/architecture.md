# Architecture d'infrastructure (production)

Vue d'ensemble de la topologie de production : applications hébergées sur
CleverCloud, bases de données, backups et services externes.

Ce document remplace l'ancien schéma Google Drawing, afin que le diagramme soit
versionné et maintenu directement dans le repo. Il est rendu nativement par
GitHub via le bloc Mermaid ci-dessous.

```mermaid
flowchart LR
    users((Utilisateurs))
    dns[DNS]
    github[GitHub<br/>source + docker]
    datagouv[data.gouv.fr]
    enroute[enRoute<br/>validation / conv. NeTEx]
    validata[validata]
    tools[transport-tools<br/>conversions GTFS→NeTEx]

    appsignal[AppSignal]
    sentry[Sentry]
    updown[Updown]
    mailjet[Mailjet]

    subgraph cc[CleverCloud — prod]
        site[prod-site<br/>site, API, proxy]
        worker[prod-worker<br/>jobs]
        pg[(prod-postgres)]
        replica[(prod-postgres<br/>réplique)]
        history[prod-transport-data-history<br/>S3 — pas de backup]
        validator[transport-validator-rust]
        metabase[prod-metabase]
        metabasepg[(prod-metabase-pg<br/>config)]
        vault[vaultwarden]
    end

    subgraph bkp[Backups]
        b1[backups postgres]
        b2[backups postgres<br/>hors site — Scaleway]
    end

    blog[blog.transport.data.gouv.fr]
    normes[normes.transport.data.gouv.fr]

    users --> dns --> site
    site --> pg
    site --> history
    worker --> pg
    worker --> history
    worker --> tools
    site & worker --> validator
    site & worker --> enroute
    pg --> replica
    pg --> b1 --> b2
    replica --> metabase --> metabasepg
```
