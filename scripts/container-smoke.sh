#!/usr/bin/env bash
#
# Starts the freshly built image under the same constraints the cluster imposes and
# confirms it serves traffic. Running it read-only, unprivileged and with every
# capability dropped means a regression in the image is caught here rather than as a
# CrashLoopBackOff after deployment.
#
# Usage: scripts/container-smoke.sh <image>

set -euo pipefail

readonly IMAGE="${1:?an image reference is required}"
readonly CONTAINER="container-smoke-$$"
readonly PORT="${PORT:-18999}"

cleanup() {
  docker rm --force "${CONTAINER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run --detach \
  --name "${CONTAINER}" \
  --publish "127.0.0.1:${PORT}:8000" \
  --read-only \
  --tmpfs /tmp \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --user 10001:10001 \
  --env APP_ENVIRONMENT=container-smoke \
  "${IMAGE}" >/dev/null

for _ in $(seq 1 30); do
  if curl --silent --fail --max-time 2 "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

readonly STATUS="$(curl --silent --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:${PORT}/healthz")"
if [[ "${STATUS}" != "200" ]]; then
  printf '[container-smoke] liveness returned %s\n' "${STATUS}" >&2
  docker logs "${CONTAINER}" >&2 || true
  exit 1
fi

readonly IDENTITY="$(docker exec "${CONTAINER}" id -u)"
if [[ "${IDENTITY}" != "10001" ]]; then
  printf '[container-smoke] container runs as uid %s, expected 10001\n' "${IDENTITY}" >&2
  exit 1
fi

printf '[container-smoke] %s serves traffic unprivileged on a read-only filesystem\n' "${IMAGE}" >&2
