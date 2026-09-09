-- Run as NFE_OWNER only for an explicitly approved batch whose manual purge
-- chunks have been committed.  This performs Object Storage downloads and
-- permanently closes the batch on success, or records BLOCKED on failure.
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

accept purge_batch_id number prompt 'Approved batch ID with all purge chunks committed: '

declare
  l_closed boolean;
  l_status nfe_migration_batch.status%type;
begin
  pkg_nfe_purge_admin.reconcile_and_close_purge(&purge_batch_id, l_closed);
  commit;
  select status into l_status from nfe_migration_batch where batch_id = &purge_batch_id;
  if not l_closed or l_status <> 'PURGED' then
    raise_application_error(-20160,
      'FAIL: post-purge reconciliation blocked the batch; inspect NFE_MIGRATION_AUDIT.');
  end if;
  dbms_output.put_line('PASS: post-purge reconciliation verified objects, absent source content, counts, and audit trail.');
exception
  when others then
    rollback;
    raise;
end;
/
