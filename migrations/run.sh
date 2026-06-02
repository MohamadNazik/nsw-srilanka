#!/bin/bash
set -euo pipefail

CLEAN_RUN=false
MIGRATIONS_FROM=""

for arg in "$@"; do
  case "$arg" in
    --clean-run)
      CLEAN_RUN=true
      ;;
    --migrations=*)
      MIGRATIONS_FROM="${arg#*=}"
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: ./run.sh [--clean-run] [--migrations=<prefix>]"
      echo "  --clean-run         Drop and recreate the database, then run all migrations"
      echo "  --migrations=013    Run migrations from prefix onwards (no drop)"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Load environment variables (skip if already injected, e.g. via Docker)
# ---------------------------------------------------------------------------
ENV_FILE_PATH="${ENV_FILE:-../.env}"

_REQUIRED_VARS_SET=true
for VAR in DB_HOST DB_PORT DB_USERNAME DB_PASSWORD DB_NAME; do
  if [ -z "${!VAR:-}" ]; then
    _REQUIRED_VARS_SET=false
    break
  fi
done

if [[ "$_REQUIRED_VARS_SET" == "false" ]]; then
  if [ -f "$ENV_FILE_PATH" ]; then
    set -o allexport
    source "$ENV_FILE_PATH"
    set +o allexport
  else
    echo "Error: env file not found: $ENV_FILE_PATH"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Validate required variables
# ---------------------------------------------------------------------------
for VAR in DB_HOST DB_PORT DB_USERNAME DB_PASSWORD DB_NAME; do
  if [ -z "${!VAR:-}" ]; then
    echo "Error: Required environment variable $VAR is not set."
    exit 1
  fi
done

MIGRATION_DB_HOST="${MIGRATION_DB_HOST:-$DB_HOST}"
MIGRATION_DB_HOST="${MIGRATION_DB_HOST//host.docker.internal/localhost}"

NPQS_OGA_SUBMISSION_URL="${NPQS_OGA_SUBMISSION_URL:-http://localhost:8081/api/v1/inject}"
FCAU_OGA_SUBMISSION_URL="${FCAU_OGA_SUBMISSION_URL:-http://localhost:8082/api/v1/inject}"
PRECONSIGNMENT_OGA_SUBMISSION_URL="${PRECONSIGNMENT_OGA_SUBMISSION_URL:-http://localhost:8083/api/v1/inject}"
CDA_OGA_SUBMISSION_URL="${CDA_OGA_SUBMISSION_URL:-http://localhost:8084/api/v1/inject}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Clean run: drop and recreate database
# ---------------------------------------------------------------------------
if [[ "$CLEAN_RUN" == "true" ]]; then
  echo "Dropping database $DB_NAME..."
  PGPASSWORD=$DB_PASSWORD psql -h "$MIGRATION_DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d postgres \
    -c "DROP DATABASE IF EXISTS $DB_NAME WITH (FORCE);"

  echo "Creating database $DB_NAME..."
  PGPASSWORD=$DB_PASSWORD psql -h "$MIGRATION_DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d postgres \
    -c "CREATE DATABASE $DB_NAME;"
fi

# ---------------------------------------------------------------------------
# Discover and filter migrations
# ---------------------------------------------------------------------------
ALL_MIGRATIONS=()
while IFS= read -r line; do
  ALL_MIGRATIONS+=("$line")
done < <(find "$SCRIPT_DIR" -maxdepth 1 -name "*.up.sql" | sort)

if [[ ${#ALL_MIGRATIONS[@]} -eq 0 ]]; then
  echo "No migration files found in $SCRIPT_DIR"
  exit 1
fi

MIGRATIONS_TO_RUN=()

if [[ "$CLEAN_RUN" == "true" ]]; then
  MIGRATIONS_TO_RUN=("${ALL_MIGRATIONS[@]}")
elif [[ -n "$MIGRATIONS_FROM" ]]; then
  for f in "${ALL_MIGRATIONS[@]}"; do
    filename="$(basename "$f")"
    if [[ "$filename" > "${MIGRATIONS_FROM}" || "$filename" == "${MIGRATIONS_FROM}"* ]]; then
      MIGRATIONS_TO_RUN+=("$f")
    fi
  done
  if [[ ${#MIGRATIONS_TO_RUN[@]} -eq 0 ]]; then
    echo "No migration files found matching or following prefix: $MIGRATIONS_FROM"
    exit 0
  fi
else
  echo "Nothing to do. Use --clean-run or --migrations=<prefix>."
  exit 0
fi

echo "Running ${#MIGRATIONS_TO_RUN[@]} migration(s)..."

# ---------------------------------------------------------------------------
# Execute migrations
# ---------------------------------------------------------------------------
for FILE in "${MIGRATIONS_TO_RUN[@]}"; do
  echo "Executing: $(basename "$FILE")"
  PGPASSWORD=$DB_PASSWORD psql \
    -v ON_ERROR_STOP=1 \
    -v NPQS_OGA_SUBMISSION_URL="$NPQS_OGA_SUBMISSION_URL" \
    -v FCAU_OGA_SUBMISSION_URL="$FCAU_OGA_SUBMISSION_URL" \
    -v PRECONSIGNMENT_OGA_SUBMISSION_URL="$PRECONSIGNMENT_OGA_SUBMISSION_URL" \
    -v CDA_OGA_SUBMISSION_URL="$CDA_OGA_SUBMISSION_URL" \
    -h "$MIGRATION_DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -f "$FILE"
done

echo "Migrations completed successfully."