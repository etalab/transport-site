#!/bin/bash

#Usage ./migrage_db.sh db_name user_name remote_db_name remove_user absolute_path_to_backup
#Use it as a postgres user

psql -c "DROP DATABASE $1"

psql -c "CREATE DATABASE $3"

psql -c "CREATE ROLE $4"

pg_restore -d $3 --format=c $5

psql -c "ALTER DATABASE $3 RENAME TO $1"

psql -c "ALTER DATABASE $1 OWNER TO $2"

for tbl in `psql -qAt -c "select tablename from pg_tables where schemaname = 'public';" $1` ; do  psql -c "alter table \"$tbl\" owner to $2" $1 ; done

for tbl in `psql -qAt -c "select sequence_name from information_schema.sequences where sequence_schema = 'public';" $1` ; do  psql -c "alter sequence \"$tbl\" owner to $2" $1 ; done

for tbl in `psql -qAt -c "select table_name from information_schema.views where table_schema = 'public';" $1` ; do  psql -c "alter view \"$tbl\" owner to $2" $1 ; done
