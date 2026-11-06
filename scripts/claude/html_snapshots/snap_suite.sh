#!/bin/bash
# usage: snap_suite.sh <out_dir> [test paths relative to apps/transport...]
# Applies the ConnCase instrumentation patch, runs the tests serially with a fixed seed (deterministic
# factory sequences), saves every HTML page served under <out_dir>/<TestModule>/, then reverts the patch.
D=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "$1")
shift
REPO=$(git -C "$D" rev-parse --show-toplevel)
cd "$REPO" || exit 1
git apply "$D/conn_case_snapshot.patch" || exit 1
trap 'cd "$REPO" && git apply -R "$D/conn_case_snapshot.patch"' EXIT
cd apps/transport || exit 1
SNAPSHOT_DIR="$OUT" mix test --seed 0 --max-cases 1 "$@" 2>&1 | grep -E "Result|^\s+[0-9]+\) test"
