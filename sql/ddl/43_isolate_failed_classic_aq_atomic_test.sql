-- Run as NFE_OWNER only to isolate the failed pre-fix atomic-admission test.
-- Supply the exact batch ID reported by the diagnostic query (for the known
-- failed execution, 42). This consumes only its exact classic-AQ message,
-- records the controlled exception, and never reads/logs payload content or
-- touches TEQ, source XML, Object Storage, or purge state.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

accept failed_batch_id number prompt 'Failed AQCL-COMMIT batch_id to isolate: '

declare
  l_batch_id    number := &failed_batch_id;
  l_batch_code  nfe_migration_batch.batch_code%type;
  l_batch_state nfe_migration_batch.status%type;
  l_control_id  nfe_migration_item.control_id%type;
  l_item_state  nfe_migration_item.status%type;
  l_correlation varchar2(100);
  l_count       pls_integer;
  l_deq         dbms_aq.dequeue_options_t;
  l_props       dbms_aq.message_properties_t;
  l_payload     raw(2000);
  l_msgid       raw(16);
begin
  select batch_code, status into l_batch_code, l_batch_state
    from nfe_migration_batch
   where batch_id = l_batch_id
   for update;
  if l_batch_code not like 'AQCL-COMMIT-%' or l_batch_state <> 'PROCESSING' then
    raise_application_error(-20210,
      'Target is not the expected failed AQCL-COMMIT batch in PROCESSING state.');
  end if;

  select control_id, status into l_control_id, l_item_state
    from nfe_migration_item
   where batch_id = l_batch_id
   for update;
  if l_item_state <> 'QUEUED' then
    raise_application_error(-20211,
      'Target test item is not QUEUED; it will not be altered.');
  end if;

  l_correlation := 'NFE-CLASSIC-' || l_control_id;
  select count(*) into l_count
    from aq$nfe_classic_aq_qt
   where corr_id = l_correlation
     and msg_state = 'READY';
  if l_count <> 1 then
    raise_application_error(-20212,
      'Expected exactly one READY classic AQ message for the target test item.');
  end if;

  l_deq.visibility := dbms_aq.on_commit;
  l_deq.dequeue_mode := dbms_aq.remove;
  l_deq.navigation := dbms_aq.first_message;
  l_deq.wait := dbms_aq.no_wait;
  l_deq.correlation := l_correlation;
  dbms_aq.dequeue('NFE_CLASSIC_AQ_Q', l_deq, l_props, l_payload, l_msgid);

  update nfe_migration_item
     set status = 'EXCEPTION',
         last_error_code = 'CLASSIC_AQ_TEST_SCOPE',
         last_error = 'Isolated after pre-fix atomic-admission test selected an unintended source row.',
         last_error_at = systimestamp
   where control_id = l_control_id;
  update nfe_migration_batch
     set status = 'BLOCKED',
         exception_count = exception_count + 1,
         last_error = 'Blocked after failed classic AQ atomic-admission test isolation.'
   where batch_id = l_batch_id;
  pkg_nfe_audit.log_event(
    p_actor_type => 'SYSTEM',
    p_event_type => 'CLASSIC_AQ_TEST_ISOLATED',
    p_batch_id => l_batch_id,
    p_control_id => l_control_id,
    p_from_status => 'QUEUED',
    p_to_status => 'EXCEPTION',
    p_correlation_id => l_correlation,
    p_details_json => '{"reason":"PRE_FIX_TEST_SCOPE"}');
  commit;

  dbms_output.put_line('PASS: failed classic AQ test batch isolated; source content and TEQ were untouched.');
exception
  when others then
    rollback;
    raise;
end;
/
