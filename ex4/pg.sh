#!/usr/bin/env bash
# Arrenca/atura la instància PostgreSQL de la pràctica (port 5435, dades a ../pgdata).
# Ús: ./pg.sh start | stop | status
exec /usr/lib/postgresql/18/bin/pg_ctl -D "$(dirname "$0")/../pgdata" -l "$(dirname "$0")/../pgdata/server.log" "${1:-status}"
