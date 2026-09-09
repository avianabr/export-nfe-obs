-- Run as NFE_OWNER after a classic AQ batch has reached VERIFIED. This is the
-- final no-purge gate: it reconciles the selected batch and requires
-- READY_FOR_APPROVAL. Supply batch 44 for the current synthetic evidence.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

accept classic_batch_id number prompt 'Verified classic AQ batch_id: '

declare
  l_batch_id number := &classic_batch_id;
  l_passed boolean;
  l_status nfe_migration_batch.status%type;
  l_count pls_integer;
begin
  select count(*) into l_count
    from nfe_migration_batch_transport
   where batch_id = l_batch_id
     and transport_mode = 'CLASSIC_AQ';
  if l_count <> 1 then
    raise_application_error(-20310, 'Batch is not explicitly selected for classic AQ.');
  end if;
  select count(*) into l_count
    from nfe_migration_item
   where batch_id = l_batch_id
     and status = 'VERIFIED'
     and source_size_bytes = object_size_bytes
     and source_sha256 = object_sha256;
  if l_count = 0 then
    raise_application_error(-20311,
      'Classic AQ batch has no integrity-verified item ready for reconciliation.');
  end if;

  pkg_nfe_reconciliation.reconcile_batch(l_batch_id, l_passed);
  select status into l_status from nfe_migration_batch where batch_id = l_batch_id;
  if not l_passed or l_status <> 'READY_FOR_APPROVAL' then
    raise_application_error(-20312,
      'Classic AQ reconciliation did not reach READY_FOR_APPROVAL.');
  end if;
  commit;
  dbms_output.put_line('PASS: classic AQ synthetic batch is reconciled and READY_FOR_APPROVAL; no purge was performed.');
exception
  when others then
    rollback;
    raise;
end;
/
