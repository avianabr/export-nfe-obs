-- Run as SYS only after all listed tables, packages and NFE_MIGRATION_Q exist.
-- If the deployment is incomplete, this script reports the missing objects and
-- exits without applying partial object or queue grants.

whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_missing varchar2(4000);
  l_queue_count pls_integer;

  procedure require_object(p_object_name varchar2, p_object_type varchar2) is
    l_count pls_integer;
  begin
    select count(*)
      into l_count
      from all_objects
     where owner = 'NFE_OWNER'
       and object_name = p_object_name
       and object_type = p_object_type
       and status = 'VALID';

    if l_count = 0 then
      l_missing := l_missing || chr(10) || ' - NFE_OWNER.' || p_object_name ||
                   ' (' || p_object_type || ')';
    end if;
  end;
begin
  require_object('PKG_NFE_MIGRATION', 'PACKAGE');
  require_object('PKG_NFE_SELECTION', 'PACKAGE');
  require_object('PKG_NFE_RECONCILIATION', 'PACKAGE');
  require_object('PKG_NFE_PURGE_ADMIN', 'PACKAGE');
  require_object('NFE_MIGRATION_BATCH', 'TABLE');
  require_object('NFE_MIGRATION_ITEM', 'TABLE');
  require_object('NFE_MIGRATION_AUDIT', 'TABLE');
  require_object('NFE_RECONCILIATION_RUN', 'TABLE');
  require_object('NFE_MIGRATION_CONFIG', 'TABLE');

  select count(*)
    into l_queue_count
    from all_queues
   where owner = 'NFE_OWNER'
     and name = 'NFE_MIGRATION_Q';

  if l_queue_count = 0 then
    l_missing := l_missing || chr(10) || ' - NFE_OWNER.NFE_MIGRATION_Q (QUEUE)';
  end if;

  if l_missing is not null then
    dbms_output.put_line('SKIPPED: deployment is incomplete. Create these objects first:' || l_missing);
  else
    execute immediate 'grant execute on nfe_owner.pkg_nfe_migration to nfe_migration_runtime';
    execute immediate 'grant execute on nfe_owner.pkg_nfe_selection to nfe_migration_runtime';
    execute immediate 'grant execute on nfe_owner.pkg_nfe_reconciliation to nfe_migration_runtime';
    execute immediate 'grant execute on nfe_owner.pkg_nfe_purge_admin to nfe_purge_admin';

    execute immediate 'grant select on nfe_owner.nfe_migration_batch to nfe_auditor';
    execute immediate 'grant select on nfe_owner.nfe_migration_item to nfe_auditor';
    execute immediate 'grant select on nfe_owner.nfe_migration_audit to nfe_auditor';
    execute immediate 'grant select on nfe_owner.nfe_reconciliation_run to nfe_auditor';
    execute immediate 'grant select on nfe_owner.nfe_migration_config to nfe_auditor';

    dbms_aqadm.grant_queue_privilege(
      privilege => 'ENQUEUE',
      queue_name => 'NFE_OWNER.NFE_MIGRATION_Q',
      grantee => 'NFE_MIGRATION_RUNTIME',
      grant_option => false);
    dbms_aqadm.grant_queue_privilege(
      privilege => 'DEQUEUE',
      queue_name => 'NFE_OWNER.NFE_MIGRATION_Q',
      grantee => 'NFE_MIGRATION_RUNTIME',
      grant_option => false);

    dbms_output.put_line('PASS: deployed-object and queue privileges were granted.');
  end if;
end;
/
