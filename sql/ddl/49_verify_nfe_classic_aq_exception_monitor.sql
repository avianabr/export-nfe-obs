-- Run as NFE_OWNER after ddl/48_create_nfe_classic_aq_exception_monitor.sql.
-- Supply the transient evidence batch after its first rollback (43 currently).
-- Three additional failed REMOVE deliveries take RETRY_COUNT from 1 to 4,
-- exceeding MAX_RETRIES=3 and forwarding the message to the exception queue.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

accept classic_batch_id number prompt 'Classic AQ exception evidence batch_id: '

declare
  l_batch_id   number := &classic_batch_id;
  l_control_id number;
  l_status     nfe_migration_item.status%type;
  l_correlation varchar2(100);
  l_enabled    char(1);
  l_processed  pls_integer;
  l_exceptions number;
begin
  pkg_nfe_classic_aq_config.get_classic_aq_enabled(l_enabled);
  if l_enabled <> 'N' then
    raise_application_error(-20270,
      'Classic AQ must be disabled before this controlled exception test.');
  end if;
  select control_id, status into l_control_id, l_status
    from nfe_migration_item
   where batch_id = l_batch_id;
  if l_status <> 'QUEUED' then
    raise_application_error(-20271, 'Exception evidence item is not QUEUED.');
  end if;
  l_correlation := 'NFE-CLASSIC-' || l_control_id;

  pkg_nfe_classic_aq_config.set_classic_aq_enabled('Y');
  commit;
  for l_attempt in 1 .. 3 loop
    begin
      pkg_nfe_classic_aq_worker.process_one(true, l_correlation);
      raise_application_error(-20272,
        'FAIL: transient simulation unexpectedly succeeded.');
    exception
      when others then
        if sqlcode = -20272 then
          raise;
        elsif sqlcode <> -20236 then
          raise;
        end if;
    end;
  end loop;

  pkg_nfe_classic_aq_exception_monitor.drain_one(l_processed, l_correlation);
  if l_processed <> 1 then
    raise_application_error(-20273, 'Exception monitor did not process the forwarded message.');
  end if;
  select status into l_status from nfe_migration_item where control_id = l_control_id;
  if l_status <> 'EXCEPTION' then
    raise_application_error(-20274, 'Item was not exposed as EXCEPTION.');
  end if;
  select exception_count into l_exceptions
    from nfe_migration_batch
   where batch_id = l_batch_id;
  if l_exceptions < 1 then
    raise_application_error(-20275, 'Batch exception count was not updated.');
  end if;

  pkg_nfe_classic_aq_config.set_classic_aq_enabled('N');
  commit;
  dbms_output.put_line('PASS: classic AQ retries forwarded to exception queue and item is EXCEPTION.');
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
