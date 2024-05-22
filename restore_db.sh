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
#
# With the flag `--preserve-oban-jobs`, Oban jobs won't be truncated. It is
# risky. Example:
# ./restore_db.sh --preserve-oban-jobs <path_to_backup>
#
# The flags must be the first args.

VALID_ARGS=$(getopt --options=h --longoptions=help,skip-extensions,preserve-oban-jobs --name "$0" -- "$@") || exit 1

eval set -- "$VALID_ARGS"

should_skip_extensions=false
should_preserve_oban_jobs=false

function usage() {
  echo "Usage:"
  echo " $0 (-h|--help) -- this message"
  echo " $0 [--skip-extensions] [--preserve-oban-jobs] <absolute_path_to_backup>"
  echo " $0 [--skip-extensions] [--preserve-oban-jobs] <db_name> <host> <user_name> <password> <absolute_path_to_backup>"
  exit 1
}

while true; do
  case "$1" in
    -h|--help)
      usage
      ;;

    --skip-extensions)
      should_skip_extensions=true
      shift 1
      ;;

    --preserve-oban-jobs)
      should_preserve_oban_jobs=true
      shift 1
      ;;

    --) shift;
      break
      ;;
  esac
done

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
    usage
fi

function sql() {
  psql -h "$HOST" -U "$USER_NAME" -d "$DB_NAME" -c "$1"
}

if [ "$should_skip_extensions" = true ]
then
  pg_restore -l "$BACKUP_PATH" -f ./pg.list
  pg_restore -h "$HOST" -U "$USER_NAME" -d "$DB_NAME" --format=c --no-owner --clean --use-list ./pg.list --no-acl "$BACKUP_PATH"
else
  pg_restore -h "$HOST" -U "$USER_NAME" -d "$DB_NAME" --format=c --no-owner --clean --no-acl "$BACKUP_PATH"
fi

echo "Truncating contact table"
sql 'TRUNCATE TABLE contact CASCADE'

echo "Truncating feedback table"
sql 'TRUNCATE TABLE feedback CASCADE'

if [ "$should_preserve_oban_jobs" = false ]
then
  echo "Truncating oban_jobs table"
  sql 'TRUNCATE TABLE oban_jobs'
fi

# Don't let database files hang around
rm "$BACKUP_PATH"

if [ "$should_skip_extensions" = true ]
then
  rm ./pg.list
fi
