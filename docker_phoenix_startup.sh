#!/usr/bin/env bash
set -euo pipefail

# wait for postgresql to be up
/opt/bin/wait-for-it.sh database:5432 --timeout=1000

# settings up the dependencies
mix deps.get
mix deps.compile
mix yarn install

# migrating the database schema
mix ecto.migrate

# starting up the server, you can visit localhost:5000/
mix phx.server
