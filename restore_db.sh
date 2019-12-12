#!/bin/bash

# Usage ./restore_db.sh <db_name> <host> <user_name> <password> <absolute_path_to_backup>
# or the ./restore_db.sh <absolute_path_to_backup> if the default options are ok for you
# the latest production backup can be fetched on "transport-site-postgresql" in clevercloud

if test "$#" -eq 1; then
    DB_NAME="transport_repo"
    USER_NAME="postgres"
    BACKUP_PATH=$1
    HOST="localhost"
    export PGPASSWORD="postgres"
elif test "$#" -eq 5; then
    DB_NAME=$1
    HOST=$2
    USER_NAME=$3
    export PGPASSWORD=$4
    BACKUP_PATH=$5
else
    echo "Usage : Usage ./restore_db.sh <db_name> <host> <user_name> <password> <absolute_path_to_backup>"
    exit 1
fi

pg_restore -h $HOST -U $USER_NAME -d $DB_NAME --format=c --no-owner --clean $BACKUP_PATH
