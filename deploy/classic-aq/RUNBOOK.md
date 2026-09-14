# Classic AQ deployment runbook

The package is safe by default. It does not create test data, start workers,
consume messages, purge anything, or interact with TEQ.

The distribution owns only `NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB`; any pre-existing
Classic AQ Scheduler job remains untouched.

## Parallel-worker operating limit

The initial supported limit is **10 concurrent workers per selected batch**.
This is a deliberately conservative deployment limit: the isolated
10,000-document benchmark completed with ten Scheduler workers in 208 seconds
(48.1 items/second), compared with 2,521 seconds for the single-worker
baseline. The limit is persisted and copied to the batch when its coordinator
is started, so a later configuration change cannot alter an active batch.

Ten workers is not a statement of general PDB or Object Storage capacity. An
increase requires an isolated PDB benchmark at each proposed level, review of
PDB CPU/session headroom and Object Storage request/error telemetry, and an
explicit operational approval. Oracle Scheduler jobs are disabled on creation
and only become runnable when enabled; the coordinator relies on that behavior
and creates no periodic job. See Oracle's [Scheduler administration
guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/administering-oracle-scheduler.html)
and [job-creation reference](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_SCHEDULER.html).

## DBMS_CLOUD prerequisite

The `NFE_OWNER` runtime packages execute with definer rights. Therefore the PDB
administrator MUST grant `EXECUTE` on the installed `DBMS_CLOUD` package
directly to `NFE_OWNER`; receiving this privilege only through a role is not
sufficient for package compilation or execution. In the PoC deployment, the
required grant is:

```sql
grant execute on c##cloud$service.dbms_cloud to nfe_owner;
grant create credential to nfe_owner;
```

Use the actual `DBMS_CLOUD` owner returned by the target PDB dictionary. A role
can govern interactive administration, but it cannot replace the direct
`EXECUTE` grant needed by the definer-rights runtime.

For a customer-managed S3-compatible endpoint, place the canonical HTTPS
authority (for example `https://nfe.obs.sa-brazil-1.myhuaweicloud.com`) once in
the local `environment.sql`. The runtime converts it to an internal `s3://...`
object URI before calling `DBMS_CLOUD`, which selects S3-compatible SigV4
authentication for unrecognized hosts. Do not put access keys, secrets, ports,
paths, query parameters, fragments, credentials, or a pre-signed URL in the
endpoint.

## Provider and integrity mode

`environment.sql` MUST set `DEPLOY_STORAGE_PROVIDER` to `S3_COMPATIBLE` or
`OCI_NATIVE`, and `DEPLOY_INTEGRITY_MODE` to `FULL_DOWNLOAD_SHA256` or
`OCI_MD5_HEAD`. S3-compatible destinations use `s3://` plus the existing full
GET/SHA-256 validation. OCI native destinations use the HTTPS Object Storage
API, require `DEPLOY_OCI_NAMESPACE`, and use `Content-MD5` plus HEAD; SHA-256
metadata is audit evidence only. The installer prompts for S3 keys only in the
S3 route and OCI signing-key fields only in the OCI route.

Before persisting `OCI_MD5_HEAD`, configuration writes a disposable object
below `<prefix>/_integrity-probe/`, verifies PUT/HEAD/DELETE and records
`OCI_HEAD_PROBE_PASSED`. Failure preserves the previous configuration. Never
use ETag as integrity evidence.

For an explicit OCI audit sample, run `audit_oci_sample(batch_id, limit, ...)`;
it performs GET/SHA-256 only for selected verified OCI items and records
`OCI_SAMPLE_AUDIT_*`, without changing item status.

The package derives the HTTP ACL host from that endpoint. The prescribed final
`SYS` installation step, `@sql/09_least_privilege.sql`, applies or preserves the
HTTP ACE for `NFE_OWNER` automatically. Do not execute a separate ACL command.
For the example above, the derived host is
`nfe.obs.sa-brazil-1.myhuaweicloud.com`; it is not a second input.

## Classic AQ prerequisite

The main orchestrator performs these steps in order. Before `00_run-installation.sql`, the PDB administrator must grant the AQ package APIs
directly to `NFE_OWNER` and grant the AQ administration role. The direct grants
are required because the runtime packages are definer-rights; the role permits
the installation to create and administer its own Classic AQ queues.

```sql
grant execute on sys.dbms_aq to nfe_owner;
grant execute on sys.dbms_aqadm to nfe_owner;
grant aq_administrator_role to nfe_owner;
grant execute on sys.dbms_crypto to nfe_owner;
grant create job to nfe_owner;
```

Do not proceed after `PLS-00201: identifier 'DBMS_AQADM' must be declared`.
Apply these grants as `SYS`, then run `sql /nolog @00_run-installation.sql`.
`DBMS_CRYPTO` is used by the runtime to produce
the SHA-256 integrity values, and `CREATE JOB` creates the deployment worker in
its disabled state.

| Phase | Executor | Command | Expected result / advance criterion | On failure |
|---|---|---|---|---|
| Prepare environment | Administrator | Copy `templates/environment.sql.template` to protected local `environment.sql`; replace all non-secret markers, including `DEPLOY_CONNECT_IDENTIFIER` | Connection and deployment configuration are available without storing secrets | Correct the one ignored local file; never commit it |
| Orchestrated installation | Operator | From `deploy/classic-aq`: `sql /nolog @00_run-installation.sql` | Prompts once, hidden, for SYS password, NFE_OWNER password, S3 access key and S3 secret key; runs every deployment phase in order | Correct the named prerequisite or credential; do not run child scripts manually |
| Rollback | `NFE_OWNER` | `@10_rollback.sql` | Gate/job disabled; no data, migrated object, queue or evidence is removed | Disable the job manually only if the reported Scheduler object is unavailable |

## Manual coordinator for a selected batch

The installation creates no recurring coordinator. After admission is complete
and only for an approved `PROCESSING` batch, the operator starts its workers
explicitly:

```sql
begin
  pkg_nfe_classic_aq_runtime.set_enabled('Y');
  commit;
  pkg_nfe_classic_aq_runtime.start_batch_workers(<batch_id>);
end;
/
```

The coordinator snapshots `NFE_CLASSIC_AQ_CONFIG.WORKER_LIMIT` (default and
supported maximum: 10), then creates at most that many jobs named
`NFE_AQ_B<batch_id>_Wnn`. It cannot choose a batch on its own. Monitor only
metadata through `V_NFE_CLASSIC_AQ_BATCH_PROGRESS`; it exposes totals, status,
worker count and failures, not XML, AQ payloads, headers or credentials.

To stop a selected batch, close the gate before disabling its jobs. This causes
the next worker iteration to leave the queue untouched; a forced stop rolls
back an in-flight dequeue so AQ can redeliver it. Use the normal rollback for a
global stop.

```sql
begin
  pkg_nfe_classic_aq_runtime.set_enabled('N');
  pkg_nfe_classic_aq_runtime.stop_batch_workers(<batch_id>);
  update nfe_migration_batch set status='BLOCKED' where batch_id=<batch_id>
    and status in ('SELECTING','PROCESSING');
  commit;
end;
/
```

The orchestrator generates a non-displayed, session-only password for
`NFE_MIGRATION_RUNTIME`, and clears every prompted or generated secret before
exiting. It does not create human auditor or purge accounts.

### Acesso humano por role

O deploy não cria nem presume contas humanas de auditoria ou purge. Quando uma
identidade individual aprovada precisar de acesso, um DBA concede somente a
role correspondente, sem compartilhar a senha de qualquer conta técnica:

```sql
grant nfe_classic_aq_auditor_r to <approved-auditor-user>;
grant nfe_classic_aq_purge_r to <approved-purge-user>;
```

`NFE_CLASSIC_AQ_AUDITOR_R` permite consultar o status e executar o monitor
suportado. `NFE_CLASSIC_AQ_PURGE_R` fica reservada para uma futura API de purge
autorizada; o pacote Classic AQ atual não instala uma API de purge. Registre a
aprovação, a identidade individual e o período de concessão antes de aplicar
qualquer role.

### Migration from the previous local-file layout

The previous `preflight-environment.sql`, `principals.sql` and
`s3-credential.sql` are no longer loaded. Create a new `environment.sql` from
its template and move only non-secret values, including
`DEPLOY_CONNECT_IDENTIFIER`, there. `00_run-installation.sql` prompts for
passwords and S3 keys and does not write them to disk. Remove
`DEPLOY_ACL_HOST`: the package derives it from `DEPLOY_S3_ENDPOINT`.

If a deployment created before 2026-09-10 reports `ORA-02290` while the
runtime moves a batch to `SELECTING` or an item to `VERIFYING`, run the explicit
owner-scoped repair below, then repeat the isolated test. It only replaces the
legacy status `CHECK` clauses; it does not drop or recreate tables or data.

```sql
@90_repair-runtime-status-constraints.sql
```

### Tablespace quota for `NFE_OWNER`

The installation creates control tables in the default tablespace of
`NFE_OWNER`. Before rerunning an installation that fails with
`ORA-01950: ... insufficient quota on tablespace SYSTEM`, the PDB administrator
can apply the following temporary PoC correction as `SYS` in the target PDB:

```sql
ALTER USER NFE_OWNER QUOTA UNLIMITED ON SYSTEM;
```

Then correct the quota and rerun `sql /nolog @00_run-installation.sql`. For a durable
environment, assign `NFE_OWNER` a dedicated application tablespace and grant
the required quota there instead of allowing application objects in `SYSTEM`.
A dedicated application tablespace may use an explicit SecureFiles policy.

## Opt-in functional test

The source mapping names all columns used by the pipeline: numeric identifier,
business key, emission date, status, and XML CLOB. The configuration API checks
simple SQL identifiers, existence, CLOB/NUMBER types where required, credential
reference, and `NFE_OWNER` read access before it replaces the active mapping.

After post-check, the administrator creates or identifies an isolated batch with
one pre-existing, authorized NF-e. Do not create source data for this test. The
batch must be `CREATED`, have a one-document limit, and use an eligible source
status. Confirm that its target NF-e has no existing control item before moving
forward.

As `NFE_OWNER`, run the following only for that isolated batch. Replace the
two SQL*Plus values with the approved batch and eligible status. For the
single-item functional test, processing remains direct; the Scheduler
coordinator is tested separately in an isolated PDB.

```sql
declare
  l_control_id number;
  l_passed     boolean;
begin
  pkg_nfe_classic_aq_runtime.set_enabled('Y');
  commit;
  pkg_nfe_classic_aq_runtime.admit_one(&batch_id, '&eligible_status', l_control_id);
  commit;
  pkg_nfe_classic_aq_runtime.process_one('NFE-CLASSIC-' || l_control_id);
  pkg_nfe_classic_aq_runtime.reconcile_batch(&batch_id, l_passed);
  commit;
  pkg_nfe_classic_aq_runtime.set_enabled('N');
  commit;
  dbms_output.put_line('control_id=' || l_control_id ||
                       ', reconciliation=' || case when l_passed then 'PASSED' else 'FAILED' end);
exception
  when others then
    pkg_nfe_classic_aq_runtime.set_enabled('N');
    commit;
    raise;
end;
/
```

Verify the selected item is `VERIFIED` and that `SOURCE_SHA256` equals
`OBJECT_SHA256`; inspect the S3-compatible URI without exposing credentials.
Then run `@10_rollback.sql` followed by `@09_postflight.sql`. Do not enable the job
permanently, create synthetic data, run purge, dequeue additional messages, or
touch TEQ.

Record the batch identifier, control identifier, object URI (without
credentials), integrity result, final `VERIFIED` state, and post-rollback status
as deployment evidence.

## Isolated synthetic scale-test data

Only when explicitly authorized for an isolated test PDB whose
`POC_NFE_DOCUMENT` table is absent or empty, the administrator may use the
separate test harnesses below as `NFE_OWNER`. They are not deployment scripts:

```sql
@../../sql/testdata/00_create_classic_aq_poc_source_table.sql
```

Run the table-creation harness only when the isolated test schema has no source
table. After confirming that the table is empty, the administrator may run:

```sql
@../../sql/testdata/05_seed_classic_aq_functional_10000.sql
```

It inserts exactly 10,000 synthetic `AUTORIZADA` NF-es and aborts without
changing anything if any source row already exists. This harness is outside the
deployment distribution, is never called by an entry point, and must not run in
a PDB containing real NF-es.

To execute the isolated 10,000-document scale test with ten concurrent
Scheduler workers, first configure the deployment with
`DEPLOY_MAX_INFLIGHT = 10000`, then run:

```sql
@../../sql/testdata/09_run_classic_aq_scale_10000_5_workers.sql
```

The harness refuses a non-isolated or previously controlled source, requires
the deployment worker job to remain disabled, creates ten disposable jobs with
1,000 messages each, reconciles all 10,000 items, and disables Classic AQ at
the end. It does not invoke purge or TEQ. Retain the printed batch ID and query
results as test evidence.

## Isolated retry test

With explicit authorization in the isolated PDB, run
`sql/testdata/06_prepare_classic_aq_retry_test.sql` as `NFE_OWNER`. It creates
one message with a non-secret invalid test credential. Run
`07_attempt_classic_aq_retry.sql` four times, waiting at least 65 seconds
between attempts because the queue retry delay is 60 seconds. Then verify the
exception count with `pkg_nfe_classic_aq_monitor.get_counts` (an exhausted
Classic AQ message appears as `MSG_STATE='EXPIRED'` with its retry count),
restore the normal configuration with `@06_configure.sql`, and run
`08_cleanup_classic_aq_retry_test.sql`. These harnesses are external to deploy,
never enable the Scheduler, and preserve the failed message in the AQ exception
queue for evidence.
