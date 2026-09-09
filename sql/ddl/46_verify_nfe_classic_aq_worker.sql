-- Run as NFE_OWNER after ddl/45_create_nfe_classic_aq_worker_package.sql.
-- Supply a known committed classic-AQ evidence batch (44 is the current one).
-- It processes its sole message through Object Storage verification and restores
-- the classic-AQ gate to disabled after the check.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

accept classic_batch_id number prompt 'Classic AQ committed evidence batch_id: '

declare
  l_batch_id    number := &classic_batch_id;
  l_control_id  number;
  l_correlation varchar2(100);
  l_status      nfe_migration_item.status%type;
  l_enabled     char(1);
  l_count       pls_integer;
begin
  pkg_nfe_classic_aq_config.get_classic_aq_enabled(l_enabled);
  if l_enabled <> 'N' then
    raise_application_error(-20240,
      'Classic AQ must be disabled before this controlled worker validation.');
  end if;

  select control_id, status
    into l_control_id, l_status
    from nfe_migration_item
   where batch_id = l_batch_id;
  if l_status <> 'QUEUED' then
    raise_application_error(-20241,
      'Evidence batch item is not QUEUED and will not be processed.');
  end if;
  l_correlation := 'NFE-CLASSIC-' || l_control_id;
  select count(*) into l_count
    from aq$nfe_classic_aq_qt
   where corr_id = l_correlation
     and msg_state = 'READY';
  if l_count <> 1 then
    raise_application_error(-20242,
      'Evidence item does not have exactly one READY classic AQ message.');
  end if;

  pkg_nfe_classic_aq_config.set_classic_aq_enabled('Y');
  commit;
  pkg_nfe_classic_aq_worker.process_one(false, l_correlation);

  select status into l_status
    from nfe_migration_item
   where control_id = l_control_id;
  if l_status <> 'VERIFIED' then
    raise_application_error(-20243, 'Worker did not persist VERIFIED status.');
  end if;
  select count(*) into l_count
    from aq$nfe_classic_aq_qt
   where corr_id = l_correlation
     and msg_state = 'READY';
  if l_count <> 0 then
    raise_application_error(-20244,
      'Worker success left a READY classic AQ message.');
  end if;

  pkg_nfe_classic_aq_config.set_classic_aq_enabled('N');
  commit;
  dbms_output.put_line('PASS: classic AQ worker committed VERIFIED state and message removal together.');
exception
  when others then
    rollback;
    begin
      pkg_nfe_classic_aq_config.set_classic_aq_enabled('N');
      commit;
    exception when others then rollback; end;
    raise;
end;
/
