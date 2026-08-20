#!/usr/bin/env bash
#
# Provisions a local Kubernetes cluster, loads the locally built image into it and
# applies the development overlay. Nothing is pulled from or pushed to a registry.
#
# Usage: scripts/kind-up.sh

set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly CLUSTER_NAME="${CLUSTER_NAME:-demonstration}"
readonly IMAGE="${IMAGE:-demonstration-service:local}"
readonly NAMESPACE="${NAMESPACE:-demonstration}"
readonly DEPLOYMENT="${DEPLOYMENT:-demonstration-service}"

log() {
  printf '[kind-up] %s\n' "$1" >&2
}

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "creating cluster ${CLUSTER_NAME}"
  kind create cluster --name "${CLUSTER_NAME}" --config "${REPOSITORY_ROOT}/k8s/kind-cluster.yaml" --wait 120s
else
  log "cluster ${CLUSTER_NAME} already exists"
fi

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  log "image ${IMAGE} not found locally; build it first with 'make build'"
  exit 1
fi

# Side-loading places the image directly in the node's container store, so the
# cluster never contacts a registry and the imagePullPolicy of IfNotPresent is
# satisfied from disk.
log "loading ${IMAGE} into the cluster"
kind load docker-image "${IMAGE}" --name "${CLUSTER_NAME}"

log "applying the development overlay"
kubectl --context "kind-${CLUSTER_NAME}" apply -k "${REPOSITORY_ROOT}/k8s/overlays/dev"

log "waiting for the rollout to complete"
if ! kubectl --context "kind-${CLUSTER_NAME}" -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT}" --timeout=180s; then
  log "rollout failed; collecting diagnostics"
  kubectl --context "kind-${CLUSTER_NAME}" -n "${NAMESPACE}" get pods -o wide || true
  kubectl --context "kind-${CLUSTER_NAME}" -n "${NAMESPACE}" describe pods || true
  kubectl --context "kind-${CLUSTER_NAME}" -n "${NAMESPACE}" logs "deployment/${DEPLOYMENT}" --all-containers --tail=100 || true
  exit 1
fi

log "cluster ready"
