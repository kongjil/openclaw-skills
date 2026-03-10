#!/usr/bin/env bash
set -Eeuo pipefail
IMAGE="calciumion/new-api:latest"
log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
if docker ps -a --format '{{.Image}}' | grep -Fxq "$IMAGE"; then
  log "skip: image still referenced by a container: $IMAGE"
  exit 0
fi
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  log "removing image: $IMAGE"
  docker rmi "$IMAGE"
  log "removed: $IMAGE"
else
  log "skip: image not found: $IMAGE"
fi
