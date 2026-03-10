#!/usr/bin/env bash
set -Eeuo pipefail

HOST_NAME="${HOST_NAME:-lingji1}"
PLAN_FILE="${PLAN_FILE:-$(dirname "$0")/backup-plan.conf}"
REMOTE_BASE="${REMOTE_BASE:-/root/tmp/staged-backups/${HOST_NAME}}"
OUT_BASE="${OUT_BASE:-${REMOTE_BASE}/out}"
STATE_BASE="${STATE_BASE:-${REMOTE_BASE}/state}"
MIN_FREE_GB="${MIN_FREE_GB:-4}"
ZSTD_LEVEL="${ZSTD_LEVEL:--3}"

mkdir -p "$OUT_BASE" "$STATE_BASE"

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "PLAN_FILE not found: $PLAN_FILE" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$PLAN_FILE"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >&2; }
free_gb() { df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4+0}'; }
ensure_space() { (( $(free_gb) >= MIN_FREE_GB )) || { echo "free space below threshold (${MIN_FREE_GB}G)" >&2; exit 3; }; }

project_is_excluded() {
  local project_name="$1" list="$2" item
  for item in $list; do
    [[ "$project_name" == "$item" ]] && return 0
  done
  return 1
}

load_items() {
  ITEM_NAMES=()
  declare -gA ITEM_MAP=()
  local item name sources

  while IFS= read -r item; do
    [[ -z "$item" || "$item" =~ ^# ]] && continue
    name="${item%%|*}"
    sources="${item#*|}"
    ITEM_NAMES+=("$name")
    ITEM_MAP["$name"]="$sources"
  done < <(printf '%s\n' "$STATIC_ITEMS")

  if [[ -n "${MYSQL_DUMP_ITEM:-}" ]]; then
    ITEM_NAMES+=("$MYSQL_DUMP_ITEM")
    ITEM_MAP["$MYSQL_DUMP_ITEM"]='__MYSQL_DUMP__'
  fi
  if [[ -n "${AUTO_CONFIG_ITEM:-}" ]]; then
    ITEM_NAMES+=("$AUTO_CONFIG_ITEM")
    ITEM_MAP["$AUTO_CONFIG_ITEM"]='__AUTO_CONFIG__'
  fi
  if [[ -n "${AUTO_DATA_ITEM:-}" ]]; then
    ITEM_NAMES+=("$AUTO_DATA_ITEM")
    ITEM_MAP["$AUTO_DATA_ITEM"]='__AUTO_DATA__'
  fi
}

build_tar_args() {
  TAR_ARGS=()
  while IFS= read -r ex; do
    [[ -z "$ex" ]] && continue
    TAR_ARGS+=("$ex")
  done < <(printf '%s\n' "$COMMON_EXCLUDES")
}

cmd_list_items() {
  printf '%s\n' "${ITEM_NAMES[@]}"
}

prepare_generated_dir() {
  local date_tag="$1" name="$2"
  local gen_dir="${STATE_BASE}/${date_tag}/generated/${name}"
  rm -rf "$gen_dir"
  mkdir -p "$gen_dir"
  printf '%s\n' "$gen_dir"
}

copy_with_parents() {
  local src="$1" dest_root="$2"
  local parent="${dest_root}$(dirname "$src")"
  mkdir -p "$parent"
  cp -a "$src" "$parent/"
}

collect_auto_config_dir() {
  local date_tag="$1" name="$2"
  local gen_dir root project path entry project_name
  gen_dir="$(prepare_generated_dir "$date_tag" "$name")"

  for root in $AUTO_PROJECT_ROOTS; do
    [[ -d "$root" ]] || continue

    for path in \
      "$root/docker-compose.yml" \
      "$root/docker-compose.yaml" \
      "$root/compose.yml" \
      "$root/compose.yaml" \
      "$root/.env"; do
      [[ -e "$path" ]] && copy_with_parents "$path" "$gen_dir"
    done

    for project in "$root"/*; do
      [[ -d "$project" ]] || continue
      project_name="$(basename "$project")"
      project_is_excluded "$project_name" "${AUTO_CONFIG_EXCLUDE_PROJECTS:-}" && continue
      for path in \
        "$project/docker-compose.yml" \
        "$project/docker-compose.yaml" \
        "$project/compose.yml" \
        "$project/compose.yaml" \
        "$project/.env"; do
        [[ -e "$path" ]] && copy_with_parents "$path" "$gen_dir"
      done
      for entry in $AUTO_CONFIG_DIR_NAMES; do
        path="$project/$entry"
        [[ -e "$path" ]] && copy_with_parents "$path" "$gen_dir"
      done
    done
  done

  if find "$gen_dir" -mindepth 1 -print -quit | grep -q .; then
    printf '%s\n' "$gen_dir"
  else
    rm -rf "$gen_dir"
    printf '__SKIP__\n'
  fi
}

collect_auto_data_paths() {
  local root project entry path ex skip project_name
  declare -A seen=()
  local -a results=()

  for root in $AUTO_DATA_ROOTS; do
    [[ -d "$root" ]] || continue
    for project in "$root"/*; do
      [[ -d "$project" ]] || continue
      project_name="$(basename "$project")"
      project_is_excluded "$project_name" "${AUTO_DATA_EXCLUDE_PROJECTS:-}" && continue
      for entry in $AUTO_DATA_DIR_NAMES; do
        path="$project/$entry"
        [[ -d "$path" ]] || continue
        skip=0
        for ex in $AUTO_DATA_EXCLUDES; do
          [[ "$(basename "$path")" == "$ex" ]] && skip=1 && break
        done
        [[ $skip -eq 1 ]] && continue
        [[ -n "${seen[$path]:-}" ]] && continue
        seen["$path"]=1
        results+=("$path")
      done
    done
  done

  printf '%s\n' "${results[@]}"
}

create_mysql_dump_dir() {
  local date_tag="$1" name="$2"
  local gen_dir dump_file container
  gen_dir="$(prepare_generated_dir "$date_tag" "$name")"
  dump_file="${gen_dir}/${MYSQL_DUMP_CONTAINER}-all.sql"
  container="${MYSQL_DUMP_CONTAINER:-}"

  [[ -n "$container" ]] || { rm -rf "$gen_dir"; printf '__SKIP__\n'; return 0; }

  if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
    log "skip mysql dump: container not running: $container"
    rm -rf "$gen_dir"
    printf '__SKIP__\n'
    return 0
  fi

  log "dumping mysql from container: $container"
  docker exec "$container" sh -lc 'exec mysqldump --single-transaction --quick --routines --events -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases' > "$dump_file"
  gzip -f "$dump_file"
  printf '%s\n' "$gen_dir"
}

resolve_item_sources() {
  local date_tag="$1" name="$2" spec
  spec="${ITEM_MAP[$name]:-}"

  case "$spec" in
    __MYSQL_DUMP__)
      create_mysql_dump_dir "$date_tag" "$name"
      ;;
    __AUTO_CONFIG__)
      collect_auto_config_dir "$date_tag" "$name"
      ;;
    __AUTO_DATA__)
      collect_auto_data_paths
      ;;
    *)
      printf '%s\n' "$spec" | tr ' ' '\n'
      ;;
  esac
}

cmd_pack_item() {
  local date_tag="$1" name="$2"
  local out_dir="${OUT_BASE}/${date_tag}"
  local state_dir="${STATE_BASE}/${date_tag}"
  local archive="${out_dir}/${name}.tar.zst"
  local sumfile="${archive}.sha256"
  local manifest="${out_dir}/${name}.manifest.txt"
  local -a srcs=()
  local -a tar_args=()
  local src

  mkdir -p "$out_dir" "$state_dir"
  ensure_space
  build_tar_args

  while IFS= read -r src; do
    [[ -z "$src" ]] && continue
    [[ "$src" == "__SKIP__" ]] && { log "skip empty item: ${name}"; printf '__SKIP__\n'; return 0; }
    if [[ -e "$src" ]]; then
      srcs+=("$src")
    else
      log "skip missing: $src"
    fi
  done < <(resolve_item_sources "$date_tag" "$name")

  if [[ ${#srcs[@]} -eq 0 ]]; then
    log "skip empty item: ${name}"
    printf '__SKIP__\n'
    return 0
  fi

  printf '%s\n' "${srcs[@]}" > "$manifest"
  tar_args+=(-I "zstd ${ZSTD_LEVEL}" -cpf "$archive")
  tar_args+=("${srcs[@]}")

  log "packing ${name} -> ${archive}"
  tar "${tar_args[@]}"
  (cd "$out_dir" && sha256sum "$(basename "$archive")" > "$(basename "$sumfile")")
  printf '%s\n' "$archive"
}

cmd_delete_item() {
  local date_tag="$1" name="$2"
  local out_dir="${OUT_BASE}/${date_tag}"
  rm -f "${out_dir}/${name}.tar.zst" "${out_dir}/${name}.tar.zst.sha256" "${out_dir}/${name}.manifest.txt"
  rm -rf "${STATE_BASE}/${date_tag}/generated/${name}"
}

cmd_finalize() {
  local date_tag="$1"
  local out_dir="${OUT_BASE}/${date_tag}"
  local final_manifest="${out_dir}/99-final-manifest.txt"
  mkdir -p "$out_dir"
  {
    echo "host=${HOST_NAME}"
    echo "date_tag=${date_tag}"
    echo "generated_at=$(date -Is)"
    printf 'items='; printf '%s,' "${ITEM_NAMES[@]}"; echo
  } > "$final_manifest"
  (cd "$out_dir" && sha256sum "$(basename "$final_manifest")" > "$(basename "$final_manifest").sha256")
  printf '%s\n' "$final_manifest"
}

cmd_cleanup_snapshot() {
  local date_tag="$1"
  rm -rf "${OUT_BASE:?}/${date_tag}" "${STATE_BASE:?}/${date_tag}"
}

main() {
  load_items
  local cmd="${1:-}"
  case "$cmd" in
    list-items)
      cmd_list_items
      ;;
    pack-item)
      [[ $# -eq 3 ]] || { echo "usage: $0 pack-item <date_tag> <item_name>" >&2; exit 64; }
      cmd_pack_item "$2" "$3"
      ;;
    delete-item)
      [[ $# -eq 3 ]] || { echo "usage: $0 delete-item <date_tag> <item_name>" >&2; exit 64; }
      cmd_delete_item "$2" "$3"
      ;;
    finalize)
      [[ $# -eq 2 ]] || { echo "usage: $0 finalize <date_tag>" >&2; exit 64; }
      cmd_finalize "$2"
      ;;
    cleanup-snapshot)
      [[ $# -eq 2 ]] || { echo "usage: $0 cleanup-snapshot <date_tag>" >&2; exit 64; }
      cmd_cleanup_snapshot "$2"
      ;;
    *)
      echo "usage: $0 {list-items|pack-item|delete-item|finalize|cleanup-snapshot}" >&2
      exit 64
      ;;
  esac
}

main "$@"
