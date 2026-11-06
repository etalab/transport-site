# Claude Code tooling

Scripts written with Claude Code for app-wide refactorings (Phoenix modernization, #3830), kept for the next
ones. Run them from the repository root.

## HTML snapshots (`html_snapshots/`)

Checks that a refactoring does not change the HTML served by the application, using the whole test suite
as page fixtures.

- `snap_suite.sh <out_dir> [test paths]`: temporarily applies `conn_case_snapshot.patch` (a telemetry
  handler in `TransportWeb.ConnCase` saving every HTML response of the endpoint, LiveView dead renders
  included), runs the tests serially with a fixed seed, saves the pages as
  `<out_dir>/<TestModule>/<test>-<n>.html`, then reverts the patch.
- `compare_tree.exs <before_dir> <after_dir> [--lines 20] [--mask-digits]`: diffs the canonical form of
  every page (sorted attributes, whitespace-only text dropped, CSRF tokens, LiveView sessions, nonces and
  times neutralized, database ids and UUIDs renumbered).

```bash
git stash                                   # or check out the base commit
scripts/claude/html_snapshots/snap_suite.sh /tmp/snapshots/before
git stash pop
scripts/claude/html_snapshots/snap_suite.sh /tmp/snapshots/after
mix run --no-start scripts/claude/html_snapshots/compare_tree.exs /tmp/snapshots/before /tmp/snapshots/after
```

Some pages differ from one run to another (e.g. NeTEx issues of equal severity, tokens, logged-in pages):
capture the baseline twice to list them. Factory sequences shift when tests are added or fail:
`--mask-digits` tells those shifts from real changes.
