# Environments

Two root modules composing the same five modules into the same topology. A change is
therefore exercised against the shape it will meet in production, and the
differences are confined to capacity and to trade-offs that are stated where they
are made.

## What differs, and why

| | `dev` | `prod` | Reason |
| --- | --- | --- | --- |
| Address space | `10.10.0.0/16` | `10.20.0.0/16` | Disjoint, so the two can be peered without renumbering |
| NAT gateways | 1 | 3, one per zone | A zone failure in development costs a restart; in production it must not sever egress for the zones that survive |
| Node capacity | Spot | On demand | Interruption is acceptable until a service level objective exists |
| Node floor | 2 | 3 | One replica per zone |
| Log retention | 30 days | 365 days | Investigation window against storage cost |
| Flow log retention | 30 days | 90 days | As above |
| Registry encryption | AWS managed | Customer managed | Access can be revoked at the key, not only at the repository policy |
| Alarm threshold | 25 errors | 10 errors | Development tolerates a noisier signal |
| Zonal spread | `ScheduleAnyway` | `DoNotSchedule` | Production must fail loudly rather than stack replicas into one zone |

Every one of these is asserted by the environment tests, so production cannot
quietly inherit a development trade-off.

## Tests

```bash
terraform -chdir=envs/dev test
terraform -chdir=envs/prod test
```

Six runs each, against a mocked provider. They cover naming derivation, stable
availability zone selection, the documented address plan, the trade-off above, the
outputs an operator is handed, and the rejection of an API allow-list containing
`0.0.0.0/0`.

## Placeholders

`operator_access_cidrs` uses `203.0.113.0/24`, reserved by RFC 5737 for
documentation. Account identifiers elsewhere use `111122223333`. Both must be
replaced before any real initialisation; neither is a working value.
