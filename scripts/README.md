# Scripts

Every verification step in this repository is a script that a developer can run
directly, and continuous integration runs those same scripts. There is no CI-only
path, so a pipeline failure always reproduces locally.

| Script | Purpose |
| --- | --- |
| `kind-up.sh` | Create the local cluster if absent, side-load the image, apply the development overlay and await the rollout. Dumps diagnostics on failure |
| `smoke-test.sh` | Exercise the deployed workload through its Service and assert the security context of the running pod. Twelve checks |
| `kind-down.sh` | Remove the local cluster. Safe when none exists |
| `container-smoke.sh` | Run a freshly built image under the same constraints the cluster imposes — read-only, unprivileged, all capabilities dropped — and confirm it serves traffic |
| `manifest-policy.py` | Render both overlays and assert the invariants schema validation cannot see. Fifty-nine checks. The only verification the production overlay receives |
| `docs-check.py` | Assert that the documentation still describes the repository: every relative link resolves, and every stated test count matches the tests that exist |

All are linted by `shellcheck` at style severity, which is what caught four cases of
`SC2155` masking the exit status of a command substitution — under `set -e` a failed
query would otherwise have passed as an empty result.

Each honours `CLUSTER_NAME`, `NAMESPACE` and `IMAGE` from the environment, so they
can be pointed at a differently named cluster without editing.
