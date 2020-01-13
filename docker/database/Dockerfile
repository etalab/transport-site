FROM mdillon/postgis:11-alpine

# PATH to the clever cloud backup file
ARG BACKUP_PATH

ENV POSTGRES_DB transport_repo

COPY restore_db.sh /docker-entrypoint-initdb.d/
COPY create_test_db.sh /docker-entrypoint-initdb.d/
COPY ${BACKUP_PATH} /db_backup


