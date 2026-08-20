#!/usr/bin/env python3
"""Assert the security and reliability invariants of the rendered manifests.

The development overlay is applied to a real cluster in continuous integration, so
its behaviour is observed directly. The production overlay never is: no cluster in
this repository can provision an Application Load Balancer or an IAM role, and
schema validation alone would accept a manifest that runs as root, pulls a mutable
tag or omits a probe.

This checker closes that gap. It renders each overlay with kustomize and asserts the
invariants that must hold for every workload, plus the ones specific to production.
Any failure exits non-zero, so it is usable directly as a pipeline gate.

Usage: scripts/manifest-policy.py [overlay ...]
"""

from __future__ import annotations

import subprocess
import sys
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import yaml

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent

# The identity the container image is built with. A mismatch here means the pod
# would be rejected by the restricted Pod Security Admission profile.
EXPECTED_UID = 10001

_failures: list[str] = []
_checks = 0


def check(description: str, condition: bool, detail: str = "") -> None:
    """Record one assertion and report it."""
    global _checks
    _checks += 1
    if condition:
        print(f"  PASS  {description}")
        return
    suffix = f" ({detail})" if detail else ""
    print(f"  FAIL  {description}{suffix}")
    _failures.append(description)


def render(overlay: Path) -> list[dict[str, Any]]:
    """Render an overlay to a list of Kubernetes objects."""
    completed = subprocess.run(
        ["kubectl", "kustomize", str(overlay)],
        capture_output=True,
        text=True,
        check=True,
    )
    return [doc for doc in yaml.safe_load_all(completed.stdout) if doc]


def of_kind(objects: list[dict[str, Any]], kind: str) -> list[dict[str, Any]]:
    return [obj for obj in objects if obj.get("kind") == kind]


def containers(pod_spec: dict[str, Any]) -> Iterator[tuple[str, dict[str, Any]]]:
    for container in pod_spec.get("containers", []):
        yield container["name"], container


def check_workload_invariants(overlay_name: str, objects: list[dict[str, Any]]) -> None:
    """Assert the invariants every environment must satisfy."""
    namespaces = of_kind(objects, "Namespace")
    check(
        f"[{overlay_name}] the namespace enforces the restricted admission profile",
        all(
            ns["metadata"]["labels"].get("pod-security.kubernetes.io/enforce") == "restricted"
            for ns in namespaces
        ),
    )

    for account in of_kind(objects, "ServiceAccount"):
        check(
            f"[{overlay_name}] service account {account['metadata']['name']} does not "
            "auto-mount its token",
            account.get("automountServiceAccountToken") is False,
        )

    policies = of_kind(objects, "NetworkPolicy")
    default_deny = [
        policy
        for policy in policies
        if policy["spec"].get("podSelector") == {}
        and set(policy["spec"].get("policyTypes", [])) == {"Ingress", "Egress"}
    ]
    check(
        f"[{overlay_name}] a default-deny network policy selects every pod",
        len(default_deny) == 1,
        f"found {len(default_deny)}",
    )

    check(
        f"[{overlay_name}] a disruption budget bounds voluntary eviction",
        len(of_kind(objects, "PodDisruptionBudget")) >= 1,
    )

    for deployment in of_kind(objects, "Deployment"):
        name = deployment["metadata"]["name"]
        pod_spec = deployment["spec"]["template"]["spec"]
        pod_security = pod_spec.get("securityContext", {})

        check(
            f"[{overlay_name}] {name} runs as a non-root user",
            pod_security.get("runAsNonRoot") is True
            and pod_security.get("runAsUser") == EXPECTED_UID,
            f"runAsUser={pod_security.get('runAsUser')}",
        )
        check(
            f"[{overlay_name}] {name} applies the default seccomp profile",
            pod_security.get("seccompProfile", {}).get("type") == "RuntimeDefault",
        )
        check(
            f"[{overlay_name}] {name} does not auto-mount a service account token",
            pod_spec.get("automountServiceAccountToken") is False,
        )
        check(
            f"[{overlay_name}] {name} allows time to drain before termination",
            pod_spec.get("terminationGracePeriodSeconds", 30) >= 30,
        )
        check(
            f"[{overlay_name}] {name} surges rather than reducing capacity during a roll",
            deployment["spec"]["strategy"]["rollingUpdate"]["maxUnavailable"] == 0,
        )

        for container_name, container in containers(pod_spec):
            label = f"[{overlay_name}] {name}/{container_name}"
            security = container.get("securityContext", {})

            check(
                f"{label} denies privilege escalation",
                security.get("allowPrivilegeEscalation") is False,
            )
            check(
                f"{label} runs on a read-only root filesystem",
                security.get("readOnlyRootFilesystem") is True,
            )
            check(
                f"{label} drops every capability",
                security.get("capabilities", {}).get("drop") == ["ALL"],
            )

            image = container.get("image", "")
            check(
                f"{label} pins an immutable image reference",
                ":" in image.rsplit("/", 1)[-1] and not image.endswith(":latest"),
                image,
            )

            resources = container.get("resources", {})
            check(
                f"{label} requests cpu and memory",
                {"cpu", "memory"} <= set(resources.get("requests", {})),
            )
            check(
                f"{label} limits memory, which is incompressible",
                "memory" in resources.get("limits", {}),
            )
            check(
                f"{label} does not limit cpu, which would throttle tail latency",
                "cpu" not in resources.get("limits", {}),
            )

            liveness = container.get("livenessProbe", {}).get("httpGet", {})
            readiness = container.get("readinessProbe", {}).get("httpGet", {})
            check(f"{label} declares a liveness probe", bool(liveness))
            check(f"{label} declares a readiness probe", bool(readiness))
            check(f"{label} declares a startup probe", bool(container.get("startupProbe")))
            check(
                f"{label} separates liveness from readiness",
                liveness.get("path") != readiness.get("path"),
                f"both target {liveness.get('path')}",
            )

            for variable in container.get("env", []):
                check(
                    f"{label} supplies no literal secret in {variable['name']}",
                    not any(
                        marker in variable["name"].upper()
                        for marker in ("SECRET", "PASSWORD", "TOKEN", "KEY")
                    )
                    or "value" not in variable,
                )


def check_production_invariants(objects: list[dict[str, Any]]) -> None:
    """Assert what production requires and no other environment does."""
    accounts = of_kind(objects, "ServiceAccount")
    annotated = [
        account
        for account in accounts
        if account["metadata"].get("annotations", {}).get("eks.amazonaws.com/role-arn")
    ]
    check("[prod] the service account is bound to an IAM role for IRSA", len(annotated) == 1)
    if annotated:
        role_arn = annotated[0]["metadata"]["annotations"]["eks.amazonaws.com/role-arn"]
        check(
            "[prod] the role annotation is a well-formed IAM role ARN",
            role_arn.startswith("arn:aws:iam::") and ":role/" in role_arn,
            role_arn,
        )

    for deployment in of_kind(objects, "Deployment"):
        constraints = deployment["spec"]["template"]["spec"].get("topologySpreadConstraints", [])
        zonal = [c for c in constraints if c["topologyKey"] == "topology.kubernetes.io/zone"]
        check(
            "[prod] zonal spread is required rather than merely preferred",
            bool(zonal) and zonal[0]["whenUnsatisfiable"] == "DoNotSchedule",
        )
        check(
            "[prod] the deployment keeps one replica per availability zone",
            deployment["spec"]["replicas"] >= 3,
        )

    ingresses = of_kind(objects, "Ingress")
    check("[prod] an ingress exposes the service", len(ingresses) == 1)
    for ingress in ingresses:
        annotations = ingress["metadata"].get("annotations", {})
        check(
            "[prod] the load balancer listens on HTTPS only",
            "HTTP\"" not in annotations.get("alb.ingress.kubernetes.io/listen-ports", "")
            and "HTTPS" in annotations.get("alb.ingress.kubernetes.io/listen-ports", ""),
        )
        check(
            "[prod] the TLS policy mandates TLS 1.2 or above",
            "TLS13" in annotations.get("alb.ingress.kubernetes.io/ssl-policy", ""),
        )
        check(
            "[prod] load balancer health checks target readiness, not liveness",
            annotations.get("alb.ingress.kubernetes.io/healthcheck-path") == "/readyz",
        )
        check(
            "[prod] targets are registered by pod address, removing the node-port hop",
            annotations.get("alb.ingress.kubernetes.io/target-type") == "ip",
        )


def main(argv: list[str]) -> int:
    overlays = argv[1:] or sorted(
        str(path) for path in (REPOSITORY_ROOT / "k8s" / "overlays").iterdir() if path.is_dir()
    )

    for overlay in overlays:
        path = Path(overlay)
        name = path.name
        print(f"[manifest-policy] {path}")
        objects = render(path)
        check_workload_invariants(name, objects)
        if name == "prod":
            check_production_invariants(objects)

    print(f"[manifest-policy] {_checks} checks, {len(_failures)} failed")
    return 1 if _failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
