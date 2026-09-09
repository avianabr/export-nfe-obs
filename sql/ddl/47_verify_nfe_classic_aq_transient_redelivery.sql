-- Run as NFE_OWNER after redeploying ddl/45_create_nfe_classic_aq_worker_package.sql.
-- Supply a committed READY classic-AQ batch reserved for the transient path
-- (43 is the current evidence batch). The simulated failure occurs before any
-- Object Storage call and must leave the item QUEUED and message eligible.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

accept classic_batch_id number prompt 'Classic AQ transient evidence batch_id: '

declare
  l_batch_id    number := &classic_batch_id;
  l_control_id  number;
  l_correlation varchar2(100);
  l_status      nfe_migration_item.status%type;
  l_enabled     char(1);
  l_count       pls_integer;
  l_retry_count number;
  l_transient_seen boolean := false;
begin
  pkg_nfe_classic_aq_config.get_classic_aq_enabled(l_enabled);
  if l_enabled <> 'N' then
    raise_application_error(-20250,
      'Classic AQ must be disabled before this controlled transient test.');
  end if;

  select control_id, status into l_control_id, l_status
    from nfe_migration_item
   where batch_id = l_batch_id;
  if l_status <> 'QUEUED' then
    raise_application_error(-20251, 'Transient evidence item is not QUEUED.');
  end if;
  l_correlation := 'NFE-CLASSIC-' || l_control_id;

  pkg_nfe_classic_aq_config.set_classic_aq_enabled('Y');
  commit;
  begin
    pkg_nfe_classic_aq_worker.process_one(true, l_correlation);
    raise_application_error(-20252, 'FAIL: transient simulation unexpectedly succeeded.');
  exception
    when others then
      if sqlcode = -20252 then
        raise;
      elsif sqlcode = -20236 then
        l_transient_seen := true;
      else
        raise;
      end if;
  end;

  select status into l_status
    from nfe_migration_item
   where control_id = l_control_id;
  if l_status <> 'QUEUED' then
    raise_application_error(-20253,
      'Transient rollback changed the item before a verified success.');
  end if;
  select count(*), max(retry_count)
    into l_count, l_retry_count
    from aq$nfe_classic_aq_qt
   where corr_id = l_correlation
     and msg_state = 'READY';
  if l_count <> 1 or nvl(l_retry_count, 0) < 1 then
    raise_application_error(-20254,
      'Transient rollback did not leave one retry-eligible classic AQ message.');
  end if;

  pkg_nfe_classic_aq_config.set_classic_aq_enabled('N');
  commit;
  if l_transient_seen then
    dbms_output.put_line('PASS: transient rollback kept item QUEUED and message READY for redelivery.');
    dbms_output.put_line('Retry count=' || l_retry_count || '; classic AQ disabled again.');
  end if;
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
