#!/bin/bash
set -e
diff <(jq --sort-keys 'del(.timeStamp)' $1) <(jq --sort-keys 'del(.timeStamp)' $2) 2>&1
