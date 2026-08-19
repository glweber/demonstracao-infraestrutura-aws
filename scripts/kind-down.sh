#!/usr/bin/env bash
#
# Removes the local cluster. Safe to run when no cluster exists.
#
# Usage: scripts/kind-down.sh

set -euo pipefail

readonly CLUSTER_NAME="${CLUSTER_NAME:-demonstration}"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind delete cluster --name "${CLUSTER_NAME}"
else
  printf '[kind-down] no cluster named %s\n' "${CLUSTER_NAME}" >&2
fi
