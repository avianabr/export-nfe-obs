-- Run as NFE_OWNER after ddl/37_create_nfe_classic_aq.sql.
-- Validates only uniquely correlated RAW test messages. It does not browse or
-- dequeue TEQ messages and leaves neither a test message nor a probe object.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  c_queue     constant varchar2(30) := 'NFE_CLASSIC_AQ_Q';
  c_exception constant varchar2(30) := 'NFE_CLASSIC_AQ_EX_Q';
  l_marker    varchar2(32) := rawtohex(sys_guid());
  l_success_correlation varchar2(128) := 'AQ-CLASSIC-SUCCESS-' || l_marker;
  l_retry_correlation   varchar2(128) := 'AQ-CLASSIC-RETRY-' || l_marker;
  l_success_payload raw(2000);
  l_retry_payload   raw(2000);
  l_received        raw(2000);
  l_msgid           raw(16);
  l_enq             dbms_aq.enqueue_options_t;
  l_deq             dbms_aq.dequeue_options_t;
  l_props           dbms_aq.message_properties_t;
  l_count           pls_integer;

  procedure dequeue_test_message(p_queue_name varchar2, p_correlation varchar2) is
    l_discard raw(2000);
    l_discard_msgid raw(16);
    l_discard_props dbms_aq.message_properties_t;
    l_discard_deq dbms_aq.dequeue_options_t;
  begin
    l_discard_deq.visibility := dbms_aq.on_commit;
    l_discard_deq.dequeue_mode := dbms_aq.remove;
    l_discard_deq.navigation := dbms_aq.first_message;
    l_discard_deq.wait := dbms_aq.no_wait;
    l_discard_deq.correlation := p_correlation;
    dbms_aq.dequeue(p_queue_name, l_discard_deq, l_discard_props,
                    l_discard, l_discard_msgid);
    commit;
  exception
    when others then
      -- ORA-25228 means the uniquely correlated cleanup message is absent.
      if sqlcode = -25228 then
        rollback;
      else
        raise;
      end if;
  end;
begin
  select count(*) into l_count from user_queues where name = c_queue;
  if l_count <> 1 then
    raise_application_error(-20160, c_queue || ' is absent.');
  end if;
  select count(*) into l_count from user_queues where name = c_exception;
  if l_count <> 1 then
    raise_application_error(-20161, c_exception || ' is absent.');
  end if;

  l_enq.visibility := dbms_aq.on_commit;
  l_success_payload := utl_raw.cast_to_raw('AQ-CLASSIC-SUCCESS-' || l_marker);
  l_props.correlation := l_success_correlation;
  l_props.exception_queue := c_exception;
  dbms_aq.enqueue(c_queue, l_enq, l_props, l_success_payload, l_msgid);
  commit;

  l_deq.visibility := dbms_aq.on_commit;
  l_deq.dequeue_mode := dbms_aq.remove;
  l_deq.navigation := dbms_aq.first_message;
  l_deq.wait := dbms_aq.no_wait;
  l_deq.correlation := l_success_correlation;
  dbms_aq.dequeue(c_queue, l_deq, l_props, l_received, l_msgid);
  if l_received <> l_success_payload then
    raise_application_error(-20162, 'Classic AQ success dequeue changed the RAW test payload.');
  end if;
  commit;

  l_retry_payload := utl_raw.cast_to_raw('AQ-CLASSIC-RETRY-' || l_marker);
  l_props.correlation := l_retry_correlation;
  l_props.exception_queue := c_exception;
  dbms_aq.enqueue(c_queue, l_enq, l_props, l_retry_payload, l_msgid);
  commit;

  -- Oracle increments RETRY_COUNT for each rolled-back REMOVE and forwards
  -- only when RETRY_COUNT is greater than MAX_RETRIES (3), hence four rolls.
  for l_attempt in 1 .. 4 loop
    l_deq.navigation := dbms_aq.first_message;
    l_deq.correlation := l_retry_correlation;
    dbms_aq.dequeue(c_queue, l_deq, l_props, l_received, l_msgid);
    rollback;
  end loop;

  l_deq.navigation := dbms_aq.first_message;
  l_deq.wait := 10;
  l_deq.correlation := l_retry_correlation;
  dbms_aq.dequeue(c_exception, l_deq, l_props, l_received, l_msgid);
  if l_received <> l_retry_payload then
    raise_application_error(-20163, 'Classic AQ exception dequeue changed the RAW test payload.');
  end if;
  commit;

  dbms_output.put_line('PASS: classic AQ RAW enqueue/dequeue, rollback redelivery, and exception routing verified.');
exception
  when others then
    rollback;
    dequeue_test_message(c_queue, l_success_correlation);
    dequeue_test_message(c_queue, l_retry_correlation);
    dequeue_test_message(c_exception, l_retry_correlation);
    raise;
end;
/
