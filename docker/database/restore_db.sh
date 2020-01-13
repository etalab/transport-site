#!/bin/bash -x

DB_NAME="transport_repo"
BACKUP_PATH="/db_backup"

# the pg_restore fail for some obscure reasons, but the import seems to be ok
pg_restore --dbname=$DB_NAME --format=c --no-owner --clean $BACKUP_PATH || true

# add a check
nb_datasets=`psql -qtAX $DB_NAME -c "select count(*) from dataset;"`

if [[ $nb_datasets -eq 0 ]]; then
    echo "no datasets loaded, something is strange"
    exit 1
fi
