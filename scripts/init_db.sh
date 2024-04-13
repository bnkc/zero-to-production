#!/usr/bin/env bash
set -x
set -eo pipefail

# Load environment variables from .env file
set -a # automatically export all variables
source .env
set +a

if ! [ -x "$(command -v psql)" ]; then
  echo >&2 "Error: psql is not installed."
  exit 1
fi

if ! [ -x "$(command -v sqlx)" ]; then
  echo >&2 "Error: sqlx is not installed."
  echo >&2 "Use:"
  echo >&2 "    cargo install --version='~0.7' sqlx-cli --no-default-features --features rustls,postgres"
  echo >&2 "to install it."
  exit 1
fi

# Allow to skip Docker if a dockerized Postgres database is already running
if [[ -z "${SKIP_DOCKER}" ]]
then
  RUNNING_POSTGRES_CONTAINER=$(docker ps --filter 'name=postgres' --format '{{.ID}}')
  if [[ -n $RUNNING_POSTGRES_CONTAINER ]]; then
    echo >&2 "There is a Postgres container already running, kill it with:"
    echo >&2 "    docker kill ${RUNNING_POSTGRES_CONTAINER}"
    exit 1
  fi
  # Launch Postgres using Docker, adapting for using DATABASE_URL
  docker run \
      -e POSTGRES_USER=$(echo $DATABASE_URL | cut -d':' -f 2 | cut -d'/' -f 3) \
      -e POSTGRES_PASSWORD=$(echo $DATABASE_URL | cut -d'@' -f 1 | cut -d':' -f 3) \
      -e POSTGRES_DB=$(echo $DATABASE_URL | cut -d'/' -f 4) \
      -p $(echo $DATABASE_URL | cut -d':' -f 4 | cut -d'/' -f 1):5432 \
      -d \
      --name "postgres_$(date '+%s')" \
      postgres -N 1000
fi

# Keep pinging Postgres until it's ready to accept commands
until PGPASSWORD=$(echo $DATABASE_URL | cut -d'@' -f 1 | cut -d':' -f 3) psql -h "$(echo $DATABASE_URL | cut -d'@' -f 2 | cut -d':' -f 1)" -U "$(echo $DATABASE_URL | cut -d':' -f 2 | cut -d'/' -f 3)" -p "$(echo $DATABASE_URL | cut -d':' -f 4 | cut -d'/' -f 1)" -d "postgres" -c '\q'; do
  >&2 echo "Postgres is still unavailable - sleeping"
  sleep 1
done

>&2 echo "Postgres is up and running on port $(echo $DATABASE_URL | cut -d':' -f 4 | cut -d'/' -f 1) - running migrations now!"

export DATABASE_URL
sqlx database create
sqlx migrate run

>&2 echo "Postgres has been migrated, ready to go!"
