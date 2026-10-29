# Architecture Decision Records (ADRs)

An ADR captures an important architectural decision — one that has a
**broad impact** on the codebase or is
**non-obvious enough to warrant documentation**. Not every technical choice
needs an ADR.

## When to create an ADR

Create an ADR when:

- The decision affects multiple modules, apps, or teams
- The tradeoff between options is non-trivial and worth recording
- Future contributors need to understand *why* something was done a certain way

Don't create an ADR for:

- Routine implementation choices (which library version, which function name)
- Bug fixes or minor refactors
- Decisions that are obvious from context

## Format

Each ADR is a Markdown file following this structure:

| Section                           | Purpose                                                       |
|-----------------------------------|---------------------------------------------------------------|
| **Context**                       | The problem or situation that prompted the decision           |
| **Decision**                      | What we chose, and why                                        |
| **Consequences**                  | Tradeoffs, effects, and things that follow from this decision |
| **Considered Options** (optional) | Alternatives we looked at and why they didn't make the cut    |

Status values:

- `proposed` — under discussion, awaiting team approval
- `accepted` — agreed upon
- `deprecated` — no longer recommended (superseded by a newer ADR)
- `superseded` — replaced by another ADR

## Naming and numbering

Files are named `NNN-short-title.md`, zero-padded to 3 digits. Numbers are never
reused. When creating a new ADR, use the next available number.

Example: `001-http-client.md`, `002-database-backup-strategy.md`

## Lifecycle

1. Draft as `proposed` in this directory
2. Discuss with the team (PR or issue)
3. Update status to `accepted` once agreed
4. If later superseded, mark the old ADR as `deprecated` and create a new one
   that supersedes it

## Resources

1. Miguel Yuste — [Architecture Decision Records](<https://adr.github.io/>).
   This is probably the most polished reference, with a gallery of examples and
   tooling.
2. Michael Nygard's original blog post — ["Documenting Architecture Decisions"](<http://thinkrelevance.com/blog/2011/11/15/documenting-architecture-decisions>)
   (2011). This is where the concept was introduced. Short, readable, and still
   the canonical source.
3. [Justin Flump's ADR template repo](<https://github.com/joelparkerhenderson/architecture-decision-record>)
   has a large collection of real-world examples in many domains. Good for seeing
   how others handle edge cases (superseding, deprecation, etc.).
