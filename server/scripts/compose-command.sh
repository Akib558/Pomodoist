# Source after setting server_dir. Overlay paths are relative to server/.
compose() {
  compose_files="$server_dir/compose.yaml"
  for overlay in ${COMPOSE_OVERLAYS:-}; do
    case "$overlay" in *[!a-zA-Z0-9_./-]*) echo "Invalid Compose overlay path" >&2; return 2;; esac
    compose_files="$compose_files:$server_dir/$overlay"
  done
  COMPOSE_FILE="$compose_files" docker compose --project-directory "$server_dir" --env-file "$server_dir/.env" "$@"
}
