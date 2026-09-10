# Classic AQ runtime distribution

Version: `1.0.0`

This distribution installs only the Classic AQ NF-e runtime. It never creates
sample NF-es, consumes a queue, purges data, or reads/modifies TEQ objects.
All scripts are SQL*Plus entry points; run them from this directory so `@@sql`
paths resolve.

| Order | Entry point | Executor | Purpose |
|---:|---|---|---|
| 1 | `provision.sql` | `SYS` | Create or validate internal principals from protected local passwords |
| 2 | `create-poc-source-table.sql` (optional) | `NFE_OWNER` | Create the empty source table only when the local mapping is `POC_NFE_DOCUMENT` |
| 3 | `preflight.sql` | `SYS` | Metadata-only checks; no runtime DDL |
| 4 | `install.sql` | `NFE_OWNER` then `SYS` as prompted | Control schema, Classic AQ, packages and least privilege |
| 5 | `configure.sql` | `NFE_OWNER` | Persist administrator-provided environment values; leaves transport off |
| 6 | `postflight.sql` | `NFE_OWNER` | Metadata-only safe-state check |
| 7 | `rollback.sql` | `NFE_OWNER` | Disable the gate and job; preserves all data and queues |

## Runtime inventory

The following is the complete, transitive deployment set. Entry points invoke
only these files; scripts in the PoC tree are reference material and are never
called by this distribution.

| Order | Script | Executor | Dependency / purpose |
|---:|---|---|---|
| 0 | `sql/00_provision_principals.sql` | `SYS` | Creates or validates internal users and private roles. |
| 1 | `sql/00_preflight.sql` | `SYS` | Read-only eligibility and conflict check; runs before runtime DDL. |
| 1 | `sql/01_control_schema.sql` | `NFE_OWNER` | Configuration, audit, gate, batch and control-item tables. |
| 2 | `sql/02_source_mapping.sql` | `NFE_OWNER` | Validated environment/source mapping API; requires control tables. |
| 3 | `sql/03_storage_config.sql` | `NFE_OWNER` | Documents the S3-compatible configuration contract; requires mapping API. |
| 4 | `sql/04_classic_aq.sql` | `NFE_OWNER` | RAW Classic AQ queue table and queues; requires the owner account and AQ administration privilege. |
| 5 | `sql/05_runtime_packages.sql` | `NFE_OWNER` | Definer-rights runtime API; requires the mapping API and control tables. |
| 6 | `sql/06_scheduler_dashboard.sql` | `NFE_OWNER` | Disabled `NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB` and status view; preserves any legacy job. |
| 7 | `sql/07_least_privilege.sql` | `SYS` | Revokes direct AQ access and grants only supported runtime/observer APIs. |
| 8 | `sql/08_postflight.sql` | `NFE_OWNER` | Read-only safe-state validation. |
| 9 | `sql/09_rollback.sql` | `NFE_OWNER` | Operational disablement only; requires installed gate and job. |

No `testdata/`, `validation/`, benchmark, purge, TEQ/ADR-evidence, cleanup, or
PoC verification script is included or transitively invoked. In particular,
the deployment never calls any `sql/ddl/*verify*`, `sql/ddl/*cleanup*`,
`sql/testdata/*`, or `sql/validation/*` file.

Required existing principals are `NFE_OWNER`, `NFE_MIGRATION_RUNTIME`,
`NFE_AUDITOR`, and `NFE_PURGE_ADMIN`. Only `NFE_OWNER` owns AQ access; callers
use definer-rights APIs and receive no direct enqueue/dequeue grant.

`create-poc-source-table.sql` is an optional, standalone environment setup
script. It is not runtime inventory and is never called by another entry point.
Use it only for the `POC_NFE_DOCUMENT` mapping; a customer source table remains
external to the deployment and must be selected through `environment.sql`.
