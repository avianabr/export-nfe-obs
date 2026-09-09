# Representative one-document batch runbook

Use this only in `PDB_POCRT_02` with the synthetic PoC dataset. The selected
document key must begin with `000020260904`; do not use this procedure for a
fiscal-production document. Keep all scheduler jobs disabled for this run.

## 1. Preflight and batch creation — `NFE_OWNER`

First re-run `sql/ddl/33_create_nfe_purge_admin_package.sql` and
`sql/security/01_grant_deployed_object_privileges.sql` (the latter as `SYS`) if
the package has changed. Seed the synthetic data if needed with
`sql/testdata/01_seed_poc_nfe_documents.sql`.

Confirm that one eligible synthetic document exists and that the pipeline is
not paused:

```sql
select pipeline_paused, max_inflight_messages, enqueue_chunk_size
from nfe_migration_config where config_id = 1;

select nfe_id, chave_nfe, situacao, data_emissao
from poc_nfe_document d
where d.chave_nfe like '000020260904%'
  and d.xml_clob is not null
  and not exists (select 1 from nfe_migration_item i where i.nfe_id = d.nfe_id)
  and rownum = 1;
```

The pipeline must be `N`. Create a one-document batch and admit one item:

```sql
var representative_batch_id number
var admitted_count number

begin
  pkg_nfe_selection.create_batch(
    p_batch_code           => 'REP-' || to_char(systimestamp, 'YYYYMMDDHH24MISSFF3'),
    p_cutoff_date          => systimestamp - interval '1' day,
    p_max_documents        => 1,
    p_selection_chunk_size => 1,
    p_eligible_situacoes   => sys.odcivarchar2list('AUTORIZADA','CANCELADA','DENEGADA'),
    p_justification        => 'One synthetic document for end-to-end purge validation.',
    p_batch_id             => :representative_batch_id);
  commit;
end;
/

begin
  pkg_nfe_migration.admit_chunk(:representative_batch_id, 1, :admitted_count);
  if :admitted_count <> 1 then
    rollback;
    raise_application_error(-20170, 'Expected exactly one synthetic document to be admitted.');
  end if;
  commit;
end;
/

print representative_batch_id
```

Copy the numeric value printed by SQL*Plus. On each new SQL*Plus connection,
set it explicitly before using the later commands:

```sql
define representative_batch_id = <numeric batch ID>
```

## 2. Transfer and reconciliation — `NFE_OWNER`

Process the one queued TEQ message, then reconcile it. Both blocks commit only
after their success condition is met.

```sql
begin
  pkg_nfe_worker.process_one;
end;
/

declare
  l_passed boolean;
begin
  pkg_nfe_reconciliation.reconcile_batch(:representative_batch_id, l_passed);
  commit;
  if not l_passed then
    raise_application_error(-20171, 'Transfer reconciliation did not pass.');
  end if;
end;
/

select b.batch_id, b.batch_code, b.status, b.reconciliation_status,
       i.control_id, i.status item_status, i.object_key,
       i.source_size_bytes, i.object_size_bytes, i.source_sha256, i.object_sha256
from nfe_migration_batch b
join nfe_migration_item i on i.batch_id = b.batch_id
where b.batch_id = :representative_batch_id;
```

Proceed only when the batch is `READY_FOR_APPROVAL`, the item is `VERIFIED`,
and both size/hash pairs agree.

## 3. Explicit approval and one-item purge — `NFE_PURGE_ADMIN`

Connect as `NFE_PURGE_ADMIN`. Confirm the batch ID and evidence reference with
the human approver, then execute the approval and purge as separate commits:

```sql
var purged_count number

begin
  nfe_owner.pkg_nfe_purge_admin.approve_batch(
    p_batch_id     => &representative_batch_id,
    p_comment      => 'Approved one-document synthetic PoC purge.',
    p_evidence_ref => 'change-ticket-or-evidence-reference');
  commit;
end;
/

begin
  nfe_owner.pkg_nfe_purge_admin.purge_batch_chunk(
    p_batch_id     => &representative_batch_id,
    p_chunk_size   => 1,
    p_purged_count => :purged_count);
  if :purged_count <> 1 then
    rollback;
    raise_application_error(-20172, 'Expected exactly one item to be purged.');
  end if;
  commit;
end;
/
```

## 4. Post-purge closure — `NFE_OWNER`

Connect back as `NFE_OWNER` and run
`sql/ddl/35_verify_nfe_post_purge_reconciliation.sql`, entering the numeric
batch ID. It downloads the object again, verifies its recorded size and hash,
checks that the source content is absent, checks audit evidence, and commits
`PURGED` only when all conditions pass.

Capture these evidence queries after success:

```sql
select batch_id, batch_code, status, approved_by, approved_at,
       purged_count, purged_at, reconciliation_status
from nfe_migration_batch
where batch_id = &representative_batch_id;

select control_id, status, source_size_bytes, object_size_bytes,
       source_sha256, object_sha256, purged_at
from nfe_migration_item
where batch_id = &representative_batch_id;

select event_at, actor, actor_type, event_type, from_status, to_status, details_json
from nfe_migration_audit
where batch_id = &representative_batch_id
order by audit_id;
```

For the sample restoration check, run
`sql/ddl/36_verify_nfe_sample_restore.sql` as `NFE_OWNER` and enter the
`CONTROL_ID` returned above. It restores only to a temporary CLOB, validates
the Object Storage bytes against the persisted hash/size evidence, records an
audit event, and does not repopulate the source row.

Record the batch ID, approved identity, object-integrity evidence, source
absence confirmation, timing, and any throughput observations in the PoC
evidence. Restoration of source content is a separate, explicitly authorized
recovery operation and is not part of this runbook.
