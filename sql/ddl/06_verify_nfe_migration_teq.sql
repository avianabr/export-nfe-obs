-- Run as NFE_OWNER after 05_create_nfe_migration_teq.sql.
-- Exercises a successful RAW enqueue/dequeue and then intentionally rolls
-- back a separate test message until TEQ forwards it to the exception queue.
-- It leaves no messages in either queue when PASS is printed.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_enqueue_options    dbms_aq.enqueue_options_t;
  l_dequeue_options    dbms_aq.dequeue_options_t;
  l_message_properties dbms_aq.message_properties_t;
  l_msgid              raw(16);
  l_payload            raw(2000);
  l_received_payload   raw(2000);
  l_retry_payload      raw(2000);
  l_exception_payload  raw(2000);
  l_marker             varchar2(32) := rawtohex(sys_guid());
  l_queue_count        pls_integer;
begin
  select count(*)
    into l_queue_count
    from user_queues
   where name = 'NFE_MIGRATION_Q';

  if l_queue_count <> 1 then
    raise_application_error(-20090,
      'NFE_MIGRATION_Q is absent.');
  end if;

  select count(*)
    into l_queue_count
    from user_queues
   where name = 'NFE_MIGRATION_EX_Q';

  if l_queue_count <> 1 then
    raise_application_error(-20091, 'NFE_MIGRATION_EX_Q is absent.');
  end if;

  l_enqueue_options.visibility := dbms_aq.on_commit;
  l_dequeue_options.visibility := dbms_aq.on_commit;
  l_dequeue_options.dequeue_mode := dbms_aq.remove;
  l_dequeue_options.wait := dbms_aq.no_wait;
  -- SQLcl can retain AQ dequeue cursor state across anonymous blocks. Reset
  -- to a fresh queue snapshot before each independent dequeue transaction.
  l_dequeue_options.navigation := dbms_aq.first_message;

  l_payload := utl_raw.cast_to_raw('TEQ-SUCCESS-' || l_marker);
  l_message_properties.correlation := 'TEQ-SUCCESS-' || l_marker;
  l_message_properties.exception_queue := null;
  dbms_aq.enqueue(
    queue_name         => 'NFE_MIGRATION_Q',
    enqueue_options    => l_enqueue_options,
    message_properties => l_message_properties,
    payload            => l_payload,
    msgid              => l_msgid);
  commit;

  l_dequeue_options.msgid := null;
  l_dequeue_options.correlation := 'TEQ-SUCCESS-' || l_marker;
  dbms_aq.dequeue(
    queue_name         => 'NFE_MIGRATION_Q',
    dequeue_options    => l_dequeue_options,
    message_properties => l_message_properties,
    payload            => l_received_payload,
    msgid              => l_msgid);

  if l_received_payload <> l_payload then
    raise_application_error(-20092, 'TEQ returned a payload different from the test payload.');
  end if;
  commit;

  l_retry_payload := utl_raw.cast_to_raw('TEQ-RETRY-' || l_marker);
  l_message_properties.correlation := 'TEQ-RETRY-' || l_marker;
  -- TEQ does not infer this association from CREATE_EQ_EXCEPTION_QUEUE.
  -- Every production work envelope will set the configured exception queue.
  l_message_properties.exception_queue := 'NFE_MIGRATION_EX_Q';
  dbms_aq.enqueue(
    queue_name         => 'NFE_MIGRATION_Q',
    enqueue_options    => l_enqueue_options,
    message_properties => l_message_properties,
    payload            => l_retry_payload,
    msgid              => l_msgid);
  commit;

  -- On this Oracle AI Database 26ai target, the third failed REMOVE for a
  -- queue with MAX_RETRIES = 3 forwards the message to its exception queue.
  -- Each rollback is deliberate and affects only this test message.
  for l_attempt in 1 .. 3 loop
    l_dequeue_options.navigation := dbms_aq.first_message;
    l_dequeue_options.msgid := null;
    l_dequeue_options.correlation := 'TEQ-RETRY-' || l_marker;
    dbms_aq.dequeue(
      queue_name         => 'NFE_MIGRATION_Q',
      dequeue_options    => l_dequeue_options,
      message_properties => l_message_properties,
      payload            => l_received_payload,
      msgid              => l_msgid);
    rollback;
  end loop;

  l_dequeue_options.navigation := dbms_aq.first_message;
  l_dequeue_options.msgid := null;
  l_dequeue_options.correlation := 'TEQ-RETRY-' || l_marker;
  l_dequeue_options.wait := 10;
  dbms_aq.dequeue(
    queue_name         => 'NFE_MIGRATION_EX_Q',
    dequeue_options    => l_dequeue_options,
    message_properties => l_message_properties,
    payload            => l_exception_payload,
    msgid              => l_msgid);

  if l_exception_payload <> l_retry_payload then
    raise_application_error(-20093,
      'Exception queue returned a payload different from the retry test payload.');
  end if;
  commit;

  dbms_output.put_line(
    'PASS: RAW TEQ enqueue/dequeue and retry forwarding to exception queue succeeded.');
exception
  when others then
    rollback;
    raise;
end;
/
