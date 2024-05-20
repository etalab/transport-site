#!/usr/bin/env bash
# NOTE: set -e cannot be used at the moment because of pg_restore will actually generate
# errors/warnings, which stops the script. A better way to handle errors must be found.

# Usage ./restore_db.sh <db_name> <host> <user_name> <password> <absolute_path_to_backup>
# or the ./restore_db.sh <absolute_path_to_backup> if the default options are ok for you
# the latest production backup can be fetched on "transport-site-postgresql" in clevercloud
#
# With the flag `--skip-extensions`, you can also skip extensions restoration as those might require administrative
# rights your pg user doesn't have. Example:
# ./restore_db.sh --skip-extensions <path_to_backup>
# The flag must be the first arg.

skip_extensions=false

if [ "$1" = "--skip-extensions" ]
then
  skip_extensions=true
  shift 1
fi

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
    echo "Usage: ./restore_db.sh (--skip-extensions) <db_name> <host> <user_name> <password> <absolute_path_to_backup>"
    exit 1
fi

if [ "$skip_extensions" = true ]
then
  pg_restore -l "$BACKUP_PATH" -f ./pg.list
  pg_restore -h "$HOST" -U "$USER_NAME" -d "$DB_NAME" --format=c --no-owner --clean --use-list ./pg.list --no-acl "$BACKUP_PATH"
else
  pg_restore -h "$HOST" -U "$USER_NAME" -d "$DB_NAME" --format=c --no-owner --clean --no-acl "$BACKUP_PATH"
fi


echo "Truncating contact table"
psql -h "$HOST" -U "$USER_NAME" -d "$DB_NAME" -c 'TRUNCATE TABLE contact CASCADE'
echo "Truncating feedback table"
psql -h "$HOST" -U "$USER_NAME" -d "$DB_NAME" -c 'TRUNCATE TABLE feedback CASCADE'

# https://stackoverflow.com/a/1885534
read -p "Do you want to remove already enqueued Oban jobs? [y/N] " -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
    psql -h "$HOST" -U "$USER_NAME" -d "$DB_NAME" -c 'DELETE from oban_jobs'
fi

# Don't let database files hang around
rm "$BACKUP_PATH"

if [ "$skip_extensions" = true ]
then
  rm ./pg.list
fi
