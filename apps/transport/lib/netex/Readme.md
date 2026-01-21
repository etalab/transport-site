# NeTEx support

- Extraction of stop places from a streamed NeTEx
- Validation of French profile via enRoute Chouette Valid
  - Ruleset generation
  - Client for enRoute Chouette Valid rulesets management API
  - French profile implementation

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
