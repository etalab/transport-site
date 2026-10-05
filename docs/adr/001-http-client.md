# 001 — HTTP Client Selection

- **Date:** 2026-10-05
- **Status:** proposed

## Context

The codebase currently uses three different HTTP client libraries: HTTPoison
(~40 call sites), Req (~6 call sites), and Finch (~10 call sites). This
fragmentation creates confusion for newcomers and makes it difficult to maintain
consistent patterns for error handling, mocking in tests, caching, and
connection management.

## Decision

**Req** is the required HTTP client for all application code. **Finch** is
derogatory — it may only be used when Req's API genuinely cannot meet the
requirement, and such use must be justified with a comment explaining why Req is
insufficient. **HTTPoison** is deprecated — no new usage should be added, and
existing call sites should eventually be migrated to Req.

Tests follow the same rule as production code. The `Transport.Req.Behaviour`
wrapper supports Mox-style mocking, so there is no excuse for using a different
client in tests.

Req uses Finch under the hood; therefore Finch is appropriate when you need to
operate below Req's abstraction (e.g., custom pool management or streaming large
payloads). This explains the two-tier model: Req is the application-level
client, Finch is the infrastructure-level primitive.

## Consequences

- New code must use Req. Using Finch is derogatory and requires a justification
  comment explaining why Req cannot satisfy the requirement.
- Reviewers enforce this rule through code review — no automated checks are introduced.
- The smaller ecosystem around Req (vs. HTTPoison) is offset by reduced maintenance
  burden: one well-maintained client instead of three.
- Existing HTTPoison call sites will be migrated over time; the cleanup of wrapper
  modules (`Transport.Shared.Wrapper.HTTPoison`, `Transport.HTTPClient`) follows
  naturally from this decision.

## Considered Options

| Client         | Notes                                                                               |
|----------------|-------------------------------------------------------------------------------------|
| Req            | Chosen — modern, actively maintained by core Elixir contributors, clean API surface |
| Finch          | Derogatory — only when Req's API is insufficient, with justification required       |
| HTTPoison      | Deprecated — older wrapper with "temporary" intent in its own docs                  |
| Tesla          | Similar wrapper concerns as HTTPoison; multiple backends adds complexity            |
| Mint / Hackney | Too low-level for application code                                                  |
