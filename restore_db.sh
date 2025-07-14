#!/usr/bin/env bash
set -e

# Usage ./restore_db.sh <db_name> <host> <user_name> <password> <absolute_path_to_backup>
# or the ./restore_db.sh <absolute_path_to_backup> if the default options are ok for you
# the latest production backup can be fetched on "transport-site-postgresql" in Clever Cloud
#
# With the flag `--skip-extensions`, you can also skip extensions restoration as those might require administrative
# rights your pg user doesn't have. Example:
# ./restore_db.sh --skip-extensions <path_to_backup>
#
# With the flag `--preserve-contacts`, contacts and related tables won't be
# truncated. It is risky. Example:
# ./restore_db.sh --preserve-contacts <path_to_backup>
#
# With the flag `--preserve-user-feedback`, user_feedback table won't be
# truncated. It is risky. Example:
# ./restore_db.sh --preserve-contacts <path_to_backup>
#
# With the flag `--preserve-oban-jobs`, Oban jobs won't be truncated. It is
# risky. Example:
# ./restore_db.sh --preserve-oban-jobs <path_to_backup>
#
# The flags must be the first args.

should_skip_extensions=false
should_preserve_contacts=true
should_preserve_user_feedback=false
should_preserve_oban_jobs=false

function usage() {
  echo "Usage:"
  echo " $0 (-h|--help)"
  echo " $0 [--skip-extensions] [--preserve-contacts] [--preserve-user-feedback] [--preserve-oban-jobs] (--) <absolute_path_to_backup>"
  echo " $0 [--skip-extensions] [--preserve-contacts] [--preserve-user-feedback] [--preserve-oban-jobs] (--) <db_name> <host> <user_name> <password> <absolute_path_to_backup>"
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

    --preserve-contacts)
      should_preserve_contacts=true
      shift 1
      ;;

    --preserve-user-feedback)
      should_preserve_user_feedback=true
      shift 1
      ;;

    --preserve-oban-jobs)
      should_preserve_oban_jobs=true
      shift 1
      ;;

    --) shift;
      break
      ;;

    --* | -*)
      echo "Unrecognized option \"$1\""
      usage
      ;;

    *) break;;
  esac
done

if test "$#" -eq 1; then
  DB_NAME="transport_repo"
  USER_NAME="transport_docker"
  BACKUP_PATH=$1
  HOST="localhost"
  PORT="6432"
  export PGPASSWORD="coucou"
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
  psql -h "$HOST" -p "$PORT" -U "$USER_NAME" -d "$DB_NAME" -c "$1"
}

if [ "$should_skip_extensions" = true ]
then
  pg_restore -l "$BACKUP_PATH" -f ./pg.list
  pg_restore -h "$HOST" -U "$USER_NAME" -d "$DB_NAME" --format=c --no-owner --clean --use-list ./pg.list --no-acl "$BACKUP_PATH"
else
  pg_restore --exit-on-error --verbose -h "$HOST" -p "$PORT" -U "$USER_NAME" -d "$DB_NAME" --format=c --no-owner --clean --if-exists --no-acl "$BACKUP_PATH"
fi

if [ "$should_preserve_contacts" = false ]
then
  echo "Truncating contact table"
  sql 'TRUNCATE TABLE contact CASCADE'
fi

if [ "$should_preserve_user_feedback" = false ]
then
  echo "Truncating user_feedback table"
  sql 'TRUNCATE TABLE user_feedback CASCADE'
fi

if [ "$should_preserve_oban_jobs" = false ]
then
  echo "Truncating oban_jobs table"
  sql 'TRUNCATE TABLE oban_jobs'
fi

# Don't let database files hang around
# rm "$BACKUP_PATH"

if [ "$should_skip_extensions" = true ]
then
  rm ./pg.list
fi
