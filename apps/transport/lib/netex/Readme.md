# NeTEx support

- How-Tos
  - How to publish the latest ruleset
  - How to list published rulesets
- Extraction of stop places from a streamed NeTEx
- Validation of French profile via enRoute Chouette Valid
  - Ruleset generation
  - Client for enRoute Chouette Valid rulesets management API
  - French profile implementation

## How-Tos

### How to publish the latest ruleset

_Prerequisite: the API token is set by the `ENROUTE_RULESETS_TOKEN` env var._

You can publish the latest ruleset to enRoute with the following command:

```bash
mix run scripts/chouette_valid_rulesets.exs publish-ruleset
```

This command will publish the latest ruleset defined in `Transport.NeTEx.FrenchProfile`
to the enRoute API. It is an upsert operation, the slug is reused if necessary.

The ruleset is an adjonction of the rules defined in `Transport.NeTEx.FrenchProfile`
which are specific to the French profile (as the name suggests) and the "base rules"
edited by enRoute. The PAN is only responsible for the french profile rules.

Later on we could envision adding rules not specific to the French profile, for
instance for data quality. It is not implemented yet nor is it planned.

### How to list published rulesets

_Prerequisite: the API token is set by the `ENROUTE_RULESETS_TOKEN` env var._

You can check what revisions are available with the following command:

```bash
mix run scripts/chouette_valid_rulesets.exs list-rulesets
```

## Extraction of stop places from a streamed NeTEx

A modest collection of helpers to extract stop places from a NeTEx archive. It
is notably useful to build the "Registre d'arrêts".

## Validation of French profile via enRoute Chouette Valid

We depend on enRoute Chouette Valid for NeTEx validation. Chouette Valid is a
SaaS.

It is extensible: one can define its own set of validation rules. This section
is therefore responsible of translating a subset of the rules from the [French
profile] to the rules model of Chouette Valid, and synchronizing it via
their API.

See <https://enroute.atlassian.net/wiki/spaces/PUBLIC/pages/2761687047/Sprint+123#Manage-rulesets-by-API>.

[French profile]: https://normes.transport.data.gouv.fr
