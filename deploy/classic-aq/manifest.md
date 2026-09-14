# Classic AQ runtime distribution

Version: `1.0.0`

This distribution installs only the Classic AQ NF-e runtime. It never creates
sample NF-es, consumes a queue, purges data, or reads/modifies TEQ objects.
All scripts are SQL*Plus entry points; run them from this directory so `@@sql`
paths resolve.

| Order | Entry point | Executor | Purpose |
|---:|---|---|---|
| 00 | `00_run-installation.sql` | Operator | Prompts for session-only secrets and orchestrates all installation phases |
| 01 | `01_create-nfe-owner.sql` | `SYS` | Orchestrator child: create or validate the deployment owner |
| 02 | `02_provision.sql` | `SYS` | Orchestrator child: create the technical runtime identity and private roles |
| 03 | `03_create-s3-credential.sql` | `NFE_OWNER` | Orchestrator child: create the named credential from session-only keys |
| 04 | `04_preflight.sql` | `SYS` | Orchestrator child: metadata-only eligibility checks |
| 05 | `05_install.sql` | `NFE_OWNER` | Orchestrator child: control schema, Classic AQ, packages and scheduler |
| 06 | `06_configure.sql` | `NFE_OWNER` | Orchestrator child: persist non-secret environment values |
| 07 | `07_show-effective-configuration.sql` | `NFE_OWNER` | Orchestrator child: read-only effective configuration display |
| 08 | `08_verify-s3-credential-preserved.sql` | `NFE_OWNER` | Orchestrator child: verify the configured credential |
| 09 | `09_postflight.sql` | `NFE_OWNER` | Orchestrator child: metadata-only safe-state check |
| 10 | `10_rollback.sql` | `NFE_OWNER` | Standalone operational rollback; not run by the installer |

## Runtime inventory

The following is the complete, transitive deployment set. Entry points invoke
only these files; scripts in the PoC tree are reference material and are never
called by this distribution.

| Order | Script | Executor | Dependency / purpose |
|---:|---|---|---|
| 00 | `sql/00_environment_defaults.sql` | SQL*Plus local input | Neutral defaults used by environment-consuming entry points; no database action. |
| 01 | `sql/01_provision_principals.sql` | `SYS` | Creates or validates internal users and private roles. |
| 02 | `sql/02_preflight.sql` | `SYS` | Read-only eligibility and conflict check; runs before runtime DDL. |
| 03 | `sql/03_control_schema.sql` | `NFE_OWNER` | Configuration, audit, gate, batch and control-item tables. |
| 04 | `sql/04_source_mapping.sql` | `NFE_OWNER` | Validated environment/source mapping API; requires control tables. |
| 05 | `sql/05_storage_config.sql` | `NFE_OWNER` | Documents the S3-compatible configuration contract; requires mapping API. |
| 06 | `sql/06_classic_aq.sql` | `NFE_OWNER` | RAW Classic AQ queue table and queues; requires the owner account and AQ administration privilege. |
| 07 | `sql/07_runtime_packages.sql` | `NFE_OWNER` | Definer-rights runtime API; requires the mapping API and control tables. |
| 08 | `sql/08_scheduler_dashboard.sql` | `NFE_OWNER` | Disabled `NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB` and status view; preserves any legacy job. |
| 09 | `sql/09_least_privilege.sql` | `SYS` | Applies the endpoint-derived ACL, revokes direct AQ access and grants only supported runtime/observer APIs. |
| 10 | `sql/10_postflight.sql` | `NFE_OWNER` | Read-only safe-state validation. |
| 11 | `sql/11_rollback.sql` | `NFE_OWNER` | Operational disablement only; requires installed gate and job. |

No `testdata/`, `validation/`, benchmark, purge, TEQ/ADR-evidence, cleanup, or
PoC verification script is included or transitively invoked. In particular,
the deployment never calls any `sql/ddl/*verify*`, `sql/ddl/*cleanup*`,
`sql/testdata/*`, or `sql/validation/*` file.

The deployment provisions `NFE_OWNER` and the technical
`NFE_MIGRATION_RUNTIME` identity. It creates private runtime, auditor and purge
roles but never creates or assumes human auditor/purge accounts. Only
`NFE_OWNER` owns AQ access; callers use definer-rights APIs and receive no
direct enqueue/dequeue grant.

`07_show-effective-configuration.sql` is a read-only diagnostic child of the
orchestrator.
It never sources a secret file and never exposes password or credential content.
