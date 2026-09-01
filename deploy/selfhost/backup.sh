#!/usr/bin/env bash

set -Eeuo pipefail

umask 077

readonly AIRTRAIL_DIR="${AIRTRAIL_DIR:-/opt/airtrail}"
readonly BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/airtrail}"

fail() {
  printf 'airtrail-backup: %s\n' "$*" >&2
  exit 1
}

[[ "$AIRTRAIL_DIR" == /* && "$AIRTRAIL_DIR" != / ]] || \
  fail "AIRTRAIL_DIR must be an absolute directory other than /"
[[ "$BACKUP_ROOT" == /* && "$BACKUP_ROOT" != / ]] || \
  fail "BACKUP_ROOT must be an absolute directory other than /"
[[ -d "$AIRTRAIL_DIR" ]] || fail "Compose directory not found: $AIRTRAIL_DIR"

for command_name in docker flock mktemp sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || \
    fail "required command not found: $command_name"
done

mkdir -p -- "$BACKUP_ROOT"
chmod 0700 -- "$BACKUP_ROOT"

exec 9>"$BACKUP_ROOT/.backup.lock"
flock -n 9 || fail "another AirTrail backup is already running"

compose() {
  docker compose --project-directory "$AIRTRAIL_DIR" "$@"
}

compose config --quiet

readonly timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
readonly final_dir="$BACKUP_ROOT/airtrail-$timestamp"
[[ ! -e "$final_dir" ]] || fail "backup destination already exists: $final_dir"
temporary_dir="$(mktemp -d "$BACKUP_ROOT/.airtrail-$timestamp.XXXXXX")"

cleanup() {
  if [[ -n "${temporary_dir:-}" && -d "$temporary_dir" ]]; then
    rm -rf -- "$temporary_dir"
  fi
}
trap cleanup EXIT

compose exec -T db sh -eu -c '
  PGPASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is not set}"
  export PGPASSWORD
  exec pg_dump \
    --format=custom \
    --compress=9 \
    --no-owner \
    --no-acl \
    --username="${POSTGRES_USER:?POSTGRES_USER is not set}" \
    --dbname="${POSTGRES_DB:?POSTGRES_DB is not set}"
' >"$temporary_dir/database.dump"

compose exec -T airtrail tar -C /app/uploads -czf - . \
  >"$temporary_dir/uploads.tar.gz"

[[ -s "$temporary_dir/database.dump" ]] || fail "database dump is empty"
[[ -s "$temporary_dir/uploads.tar.gz" ]] || fail "uploads archive is empty"

(
  cd "$temporary_dir"
  sha256sum database.dump uploads.tar.gz >SHA256SUMS
)

mv -- "$temporary_dir" "$final_dir"
temporary_dir=''

printf 'AirTrail backup written to %s\n' "$final_dir"
