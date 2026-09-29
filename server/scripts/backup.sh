#!/bin/sh
set -eu

server_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$server_dir/scripts/compose-command.sh"
backup_dir=${1:-"$server_dir/backups"}
umask 077
mkdir -p "$backup_dir"
backup_file="$backup_dir/pomodoist-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/pomodoist-backup.XXXXXX")
running_services=
finish() {
  if [ -n "$running_services" ]; then compose start $running_services >/dev/null; fi
  rm -rf "$work_dir"
}
trap finish EXIT HUP INT TERM

LC_ALL=C
source_ledger="$work_dir/source-migrations"
for migration in "$server_dir"/supabase/migrations/*.sql; do
  [ -f "$migration" ] || continue
  checksum=$(openssl dgst -sha256 "$migration" | awk '{print $NF}')
  printf '%s|%s\n' "$(basename "$migration" .sql)" "$checksum"
done > "$source_ledger"
[ -s "$source_ledger" ] || { echo "No migrations found" >&2; exit 1; }
compose exec -T db psql -X -U postgres -d postgres \
  -AtF '|' -c 'select version, checksum from pomodoist_meta.schema_migrations order by version' \
  > "$work_dir/installed-migrations"
cmp -s "$source_ledger" "$work_dir/installed-migrations" || {
  echo "Database migration ledger does not match the checked-in migrations" >&2
  exit 1
}
release_fingerprint=$(
  { cat "$source_ledger"; cat "$server_dir/compose.yaml"; for overlay in ${COMPOSE_OVERLAYS:-}; do cat "$server_dir/$overlay"; done; } |
    openssl dgst -sha256 | awk '{print $NF}'
)

storage_backup=false
case " ${COMPOSE_OVERLAYS:-} " in *" compose.storage.yaml "*) storage_backup=true;; esac
if [ "$storage_backup" = true ]; then
  command -v aws >/dev/null || { echo "AWS CLI v2 is required for Storage backups" >&2; exit 1; }
  running_services=$(compose ps --status running --services | grep -E '^(web|functions|gateway|realtime|rest|auth|storage)$' || true)
  [ -z "$running_services" ] || compose stop $running_services >/dev/null
  python3 "$server_dir/scripts/storage-objects.py" backup "$work_dir/storage.tar.gz"
else
  object_count=0
  if [ "$(compose exec -T db psql -X -U postgres -d postgres -Atc "select to_regclass('storage.objects') is not null")" = t ]; then
    object_count=$(compose exec -T db psql -X -U postgres -d postgres -Atc 'select count(*) from storage.objects')
  fi
  [ "$object_count" = 0 ] || { echo "Storage objects exist: use COMPOSE_OVERLAYS=compose.storage.yaml to include their bytes" >&2; exit 1; }
fi

printf '%s%s\n' '-- pomodoist-release-fingerprint: ' "$release_fingerprint" \
  > "$work_dir/database.sql"
compose exec -T db \
  pg_dump -U supabase_admin --data-only --disable-triggers \
    --schema=auth --schema=public --schema=private --schema=billing \
    --schema=pomodoist_meta --schema=vault --schema=storage postgres \
  >> "$work_dir/database.sql"
compose cp \
  db:/etc/postgresql-custom/pgsodium_root.key "$work_dir/pgsodium_root.key" >/dev/null
set -- database.sql pgsodium_root.key
[ "$storage_backup" = false ] || set -- "$@" storage.tar.gz
tar -C "$work_dir" -czf "$backup_file" "$@"

tar -tzf "$backup_file" >/dev/null
tar -tvzf "$backup_file" | awk -v count="$#" '
  substr($1, 1, 1) != "-" { invalid = 1 }
  END { exit(invalid || NR != count) }
'
echo "$backup_file"
