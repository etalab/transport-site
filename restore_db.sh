#!/bin/bash

#Usage ./restore_db.sh db_name user_name absolute_path_to_backup
#Use it as a postgres user

if test "$#" -eq 1; then
    DB_NAME="transport_repo"
    USER_NAME="postgres"
    BACKUP_PATH=$1
    OPTIONS="-h database -U postgres -d postgres"
    export PGPASSWORD="example"
elif test "$#" -eq 3; then
    DB_NAME=$1
    USER_NAME=$2
    BACKUP_PATH=$3
    OPTIONS=""
else
    echo "Usage : Usage ./restore_db.sh db_name user_name absolute_path_to_backup local_user"
    exit 1
fi


psql $OPTIONS -c "DROP DATABASE IF EXISTS $DB_NAME"

psql $OPTIONS -c "CREATE DATABASE $DB_NAME"

pg_restore $OPTIONS -d $DB_NAME --format=c --no-owner $BACKUP_PATH

psql $OPTIONS -c "ALTER DATABASE $DB_NAME OWNER TO $USER_NAME"

for tbl in `psql $OPTIONS -qAt -c "select tablename from pg_tables where schemaname = 'public';" -d $DB_NAME` ; do  psql $OPTIONS -c "alter table \"$tbl\" owner to $USER_NAME" -d $DB_NAME ; done

for tbl in `psql $OPTIONS -qAt -c "select sequence_name from information_schema.sequences where sequence_schema = 'public';" -d $DB_NAME` ; do  psql $OPTIONS -c "alter sequence \"$tbl\" owner to $USER_NAME" -d $DB_NAME ; done

for tbl in `psql $OPTIONS -qAt -c "select table_name from information_schema.views where table_schema = 'public';" -d $DB_NAME` ; do  psql $OPTIONS -c "alter view \"$tbl\" owner to $USER_NAME" -d $DB_NAME ; done
