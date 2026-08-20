#!/usr/bin/env bash
#
# Exercises the deployed workload through the cluster Service and asserts the
# contract each endpoint is required to honour. Any failure exits non-zero, so the
# script is usable directly as a continuous integration gate.
#
# Usage: scripts/smoke-test.sh

set -euo pipefail

readonly CLUSTER_NAME="${CLUSTER_NAME:-demonstration}"
readonly NAMESPACE="${NAMESPACE:-demonstration}"
readonly SERVICE="${SERVICE:-demonstration-service}"
readonly LOCAL_PORT="${LOCAL_PORT:-18080}"
readonly CONTEXT="kind-${CLUSTER_NAME}"

failures=0

log() {
  printf '[smoke-test] %s\n' "$1" >&2
}

check() {
  local description="$1" expected="$2" actual="$3"

  if [[ "${expected}" == "${actual}" ]]; then
    printf '  PASS  %s\n' "${description}"
  else
    printf '  FAIL  %s (expected %s, got %s)\n' "${description}" "${expected}" "${actual}"
    failures=$((failures + 1))
  fi
}

# Port-forwarding targets the Service rather than a pod, so the check also proves
# that the selector matches and that an endpoint has been registered.
kubectl --context "${CONTEXT}" -n "${NAMESPACE}" port-forward "service/${SERVICE}" "${LOCAL_PORT}:80" >/dev/null 2>&1 &
readonly FORWARD_PID=$!
trap 'kill "${FORWARD_PID}" 2>/dev/null || true' EXIT

for _ in $(seq 1 30); do
  if curl --silent --fail --max-time 2 "http://127.0.0.1:${LOCAL_PORT}/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

readonly BASE_URL="http://127.0.0.1:${LOCAL_PORT}"

log "checking endpoint contracts"
check "liveness answers 200" "200" "$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/healthz")"
check "readiness answers 200" "200" "$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/readyz")"
check "metadata answers 200" "200" "$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/")"
check "metrics answers 200" "200" "$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/metrics")"
check "unknown route answers 404" "404" "$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/absent")"
check "environment reports the overlay" "dev" "$(curl -s "${BASE_URL}/" | sed -n 's/.*"environment":"\([^"]*\)".*/\1/p')"
check "metrics expose the request counter" "present" \
  "$(curl -s "${BASE_URL}/metrics" | grep -q '^http_requests_total' && echo present || echo absent)"

log "checking the security context applied to the running pod"
# Declared separately from the assignment so that a failure of the query is not
# masked by the exit status of the declaration itself.
POD="$(kubectl --context "${CONTEXT}" -n "${NAMESPACE}" get pods -l app.kubernetes.io/name="${SERVICE}" -o jsonpath='{.items[0].metadata.name}')"
readonly POD

if [[ -z "${POD}" ]]; then
  log "no pod matched the service selector"
  exit 1
fi
check "container runs as uid 10001" "10001" \
  "$(kubectl --context "${CONTEXT}" -n "${NAMESPACE}" get pod "${POD}" -o jsonpath='{.spec.securityContext.runAsUser}')"
check "root filesystem is read-only" "true" \
  "$(kubectl --context "${CONTEXT}" -n "${NAMESPACE}" get pod "${POD}" -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}')"
check "privilege escalation is denied" "false" \
  "$(kubectl --context "${CONTEXT}" -n "${NAMESPACE}" get pod "${POD}" -o jsonpath='{.spec.containers[0].securityContext.allowPrivilegeEscalation}')"
check "all capabilities are dropped" "ALL" \
  "$(kubectl --context "${CONTEXT}" -n "${NAMESPACE}" get pod "${POD}" -o jsonpath='{.spec.containers[0].securityContext.capabilities.drop[0]}')"
check "the pod is admitted under the restricted profile" "restricted" \
  "$(kubectl --context "${CONTEXT}" get namespace "${NAMESPACE}" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')"

if (( failures > 0 )); then
  log "${failures} check(s) failed"
  exit 1
fi

log "all checks passed"
