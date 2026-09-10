# Classic AQ deployment runbook

The package is safe by default. It does not create test data, start workers,
consume messages, purge anything, or interact with TEQ.

The distribution owns only `NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB`; any pre-existing
Classic AQ Scheduler job remains untouched.

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

For a customer-managed S3-compatible endpoint, keep the administrator-supplied
endpoint in `environment.sql` as `https://...`. The runtime converts it to an
internal `s3://...` object URI before calling `DBMS_CLOUD`, which selects
S3-compatible SigV4 authentication for unrecognized hosts. Do not put access
keys, secrets, query parameters, or a pre-signed URL in the endpoint.

The target PDB must also grant `NFE_OWNER` network `http` access to the exact
endpoint host. `DEPLOY_ACL_HOST` in `preflight-environment.sql` and
`p_acl_host` in `environment.sql` MUST be that same host. For an endpoint
`https://nfe.obs.sa-brazil-1.myhuaweicloud.com`, both values are
`nfe.obs.sa-brazil-1.myhuaweicloud.com`. As `SYS`, run:

```sql
begin
  dbms_network_acl_admin.append_host_ace(
    host => 'nfe.obs.sa-brazil-1.myhuaweicloud.com',
    ace  => xs$ace_type(
      privilege_list => xs$name_list('http'),
      principal_name => 'NFE_OWNER',
      principal_type => xs_acl.ptype_db,
      granted        => true));
end;
/
```

`APPEND_HOST_ACE` is safe to rerun for an existing matching ACE. Use the host
from local `preflight-environment.sql` for another environment. Oracle's ACL
model grants network privileges through a host ACE for the database principal.

## Classic AQ prerequisite

Before `preflight.sql`, the PDB administrator must grant the AQ package APIs
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
Apply these grants as `SYS`, rerun `@preflight.sql`, and only then rerun
`@install.sql` as `NFE_OWNER`. `DBMS_CRYPTO` is used by the runtime to produce
the SHA-256 integrity values, and `CREATE JOB` creates the deployment worker in
its disabled state.

| Phase | Executor | Command | Expected result / advance criterion | On failure |
|---|---|---|---|---|
| Provision principals | `SYS` | Copy `templates/principals.sql.template` to protected local `principals.sql`, replace markers, then run `@provision.sql` | Internal runtime, auditor and purge users/roles are created or validated | Correct the protected password file or named incompatible principal; do not alter it automatically |
| Create PoC source (optional) | `NFE_OWNER` | When local `environment.sql` maps `POC_NFE_DOCUMENT` and the schema is empty, run `@create-poc-source-table.sql` | Empty table with the mapped `NUMBER`, `CLOB`, key, date and status columns exists | Do not rerun over an existing table; use the actual source table and adjust the local mapping instead |
| Create S3 credential | `NFE_OWNER` | Copy `templates/s3-credential.sql.template` to protected local `s3-credential.sql`, replace markers, then run `@create-s3-credential.sql` | Local DBMS_CLOUD credential exists without its secret entering version control | Correct the protected local file; existing credential is never replaced automatically |
| Verify S3 credential preservation | `NFE_OWNER` | `@verify-s3-credential-preserved.sql` | Configured credential is present; no protected key file is loaded | Restore or create the configured credential through the approved procedure |
| Prerequisites | `SYS` | Copy `templates/preflight-environment.sql.template` to protected local `preflight-environment.sql`, replace markers, then run `@preflight.sql` | `PASS`; required PDB, accounts, `DBMS_CLOUD`, S3 endpoint/bucket/prefix, credential and ACL metadata exist | Correct the named prerequisite; do not run install |
| Install | `NFE_OWNER` | `@install.sql` | Runtime objects and RAW Classic AQ queues exist; job is disabled | Stop on conflict; never drop/recreate the reported object |
| Privileges | `SYS` | `@sql/07_least_privilege.sql` | Runtime and auditor API grants are assigned to their private roles; callers have no direct AQ queue grants | Reconcile declared accounts/roles and rerun this step |
| Configure | `NFE_OWNER` | Copy `templates/environment.sql.template` to protected local `environment.sql`, replace markers, then run `@configure.sql` | Mapping and S3-compatible values persist; gate, job, and batch selection remain disabled | Correct markers, credentials, ACL or source access; active mapping is preserved on error |
| Post-check | `NFE_OWNER` | `@postflight.sql` | Gate and job are disabled | Run `@rollback.sql`, investigate, then repeat post-check |
| Rollback | `NFE_OWNER` | `@rollback.sql` | Gate/job disabled; no data, migrated object, queue or evidence is removed | Disable the job manually only if the reported Scheduler object is unavailable |

If a deployment created before 2026-09-10 reports `ORA-02290` while the
runtime moves a batch to `SELECTING` or an item to `VERIFYING`, run the explicit
owner-scoped repair below, then repeat the isolated test. It only replaces the
legacy status `CHECK` clauses; it does not drop or recreate tables or data.

```sql
@repair-runtime-status-constraints.sql
```

### Tablespace quota for `NFE_OWNER`

The installation creates control tables in the default tablespace of
`NFE_OWNER`. Before rerunning an installation that fails with
`ORA-01950: ... insufficient quota on tablespace SYSTEM`, the PDB administrator
can apply the following temporary PoC correction as `SYS` in the target PDB:

```sql
ALTER USER NFE_OWNER QUOTA UNLIMITED ON SYSTEM;
```

Then reconnect as `NFE_OWNER` and rerun `@install.sql`. For a durable
environment, assign `NFE_OWNER` a dedicated application tablespace and grant
the required quota there instead of allowing application objects in `SYSTEM`.
The optional `create-poc-source-table.sql` deliberately uses the default LOB
storage so it also works when the owner still defaults to `SYSTEM`; a dedicated
application tablespace may use an explicit SecureFiles policy instead.

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
two SQL*Plus values with the approved batch and eligible status. The Scheduler
job remains disabled throughout.

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
Then run `@rollback.sql` followed by `@postflight.sql`. Do not enable the job
permanently, create synthetic data, run purge, dequeue additional messages, or
touch TEQ.

Record the batch identifier, control identifier, object URI (without
credentials), integrity result, final `VERIFIED` state, and post-rollback status
as deployment evidence.

## Isolated synthetic scale-test data

Only when explicitly authorized for an isolated test PDB whose
`POC_NFE_DOCUMENT` table is empty, the administrator may run the separate
test harness below as `NFE_OWNER`:

```sql
@../../sql/testdata/05_seed_classic_aq_functional_10000.sql
```

It inserts exactly 10,000 synthetic `AUTORIZADA` NF-es and aborts without
changing anything if any source row already exists. This harness is outside the
deployment distribution, is never called by an entry point, and must not run in
a PDB containing real NF-es.

## Isolated retry test

With explicit authorization in the isolated PDB, run
`sql/testdata/06_prepare_classic_aq_retry_test.sql` as `NFE_OWNER`. It creates
one message with a non-secret invalid test credential. Run
`07_attempt_classic_aq_retry.sql` four times, waiting at least 65 seconds
between attempts because the queue retry delay is 60 seconds. Then verify the
exception count with `pkg_nfe_classic_aq_monitor.get_counts` (an exhausted
Classic AQ message appears as `MSG_STATE='EXPIRED'` with its retry count),
restore the normal configuration with `@configure.sql`, and run
`08_cleanup_classic_aq_retry_test.sql`. These harnesses are external to deploy,
never enable the Scheduler, and preserve the failed message in the AQ exception
queue for evidence.
