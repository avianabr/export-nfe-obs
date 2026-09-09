-- Run as NFE_OWNER in PDB_POCRT_02 after task 1.1 is evidenced.
--
-- This is an isolated go/no-go probe for the classic (non-TEQ) AQ API subset
-- available in Oracle 19c. It creates a uniquely named, persistent,
-- single-consumer RAW queue table; proves one ON_COMMIT enqueue/dequeue; and
-- removes every probe object. It never references NFE_MIGRATION_Q or
-- NFE_MIGRATION_EX_Q.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  c_queue_table constant varchar2(30) := 'NFE_AQ19C_PROBE_QT';
  c_queue       constant varchar2(30) := 'NFE_AQ19C_PROBE_Q';
  c_exception   constant varchar2(30) := 'NFE_AQ19C_PROBE_EX_Q';
  l_marker      varchar2(32) := rawtohex(sys_guid());
  l_payload     raw(2000);
  l_received    raw(2000);
  l_msgid       raw(16);
  l_enq         dbms_aq.enqueue_options_t;
  l_deq         dbms_aq.dequeue_options_t;
  l_props       dbms_aq.message_properties_t;
  l_count       pls_integer;
  l_compatible  user_queue_tables.compatible%type;
  l_object_type user_queue_tables.object_type%type;

  procedure require_absent(p_object_name varchar2) is
  begin
    select count(*)
      into l_count
      from user_objects
     where object_name = p_object_name
       and object_type in ('TABLE', 'QUEUE', 'INDEX');

    if l_count <> 0 then
      raise_application_error(-20130,
        p_object_name || ' already exists. The compatibility probe will not alter it.');
    end if;
  end;

  procedure remove_probe is
  begin
    begin dbms_aqadm.stop_queue(c_queue, true, true); exception when others then null; end;
    begin dbms_aqadm.stop_queue(c_exception, false, true); exception when others then null; end;
    begin dbms_aqadm.drop_queue(c_queue); exception when others then null; end;
    begin dbms_aqadm.drop_queue(c_exception); exception when others then null; end;
    begin dbms_aqadm.drop_queue_table(c_queue_table, false); exception when others then null; end;
  end;
begin
  require_absent(c_queue_table);
  require_absent(c_queue);
  require_absent(c_exception);

  -- CREATE_QUEUE_TABLE/CREATE_QUEUE/START_QUEUE and RAW DBMS_AQ calls are
  -- classic AQ interfaces available in 19c. No TxEventQ or sharded attribute
  -- is supplied; the database default compatibility is retained deliberately.
  dbms_aqadm.create_queue_table(
    queue_table        => c_queue_table,
    queue_payload_type => 'RAW',
    multiple_consumers => false,
    comment            => 'Disposable 19c-compatible classic AQ API probe');

  dbms_aqadm.create_queue(
    queue_name  => c_queue,
    queue_table => c_queue_table,
    queue_type  => dbms_aqadm.normal_queue,
    max_retries => 3,
    retry_delay => 0,
    comment     => 'Disposable classic AQ normal queue');

  dbms_aqadm.create_queue(
    queue_name  => c_exception,
    queue_table => c_queue_table,
    queue_type  => dbms_aqadm.exception_queue,
    comment     => 'Disposable classic AQ exception queue');

  dbms_aqadm.start_queue(c_queue, true, true);
  dbms_aqadm.start_queue(c_exception, false, true);

  select compatible, object_type
    into l_compatible, l_object_type
    from user_queue_tables
   where queue_table = c_queue_table;

  if l_object_type is not null then
    raise_application_error(-20131,
      'Probe queue table is not a RAW classic queue table (OBJECT_TYPE=' || l_object_type || ').');
  end if;

  l_payload := utl_raw.cast_to_raw('AQ19C-PROBE-' || l_marker);
  l_props.correlation := 'AQ19C-PROBE-' || l_marker;
  l_props.exception_queue := c_exception;
  l_enq.visibility := dbms_aq.on_commit;
  dbms_aq.enqueue(c_queue, l_enq, l_props, l_payload, l_msgid);
  commit;

  l_deq.visibility := dbms_aq.on_commit;
  l_deq.dequeue_mode := dbms_aq.remove;
  l_deq.navigation := dbms_aq.first_message;
  l_deq.wait := dbms_aq.no_wait;
  l_deq.correlation := 'AQ19C-PROBE-' || l_marker;
  dbms_aq.dequeue(c_queue, l_deq, l_props, l_received, l_msgid);

  if l_received <> l_payload then
    raise_application_error(-20132, 'Classic AQ probe returned a different RAW payload.');
  end if;
  commit;

  dbms_output.put_line('PASS: classic AQ 19c API subset accepted.');
  dbms_output.put_line('Queue table=' || c_queue_table ||
                       ', payload=RAW, consumers=SINGLE, compatible=' ||
                       nvl(l_compatible, 'DATABASE DEFAULT') ||
                       ', max_retries=3, retry_delay=0.');
  remove_probe;
  dbms_output.put_line('PASS: probe objects removed; no TEQ object was referenced.');
exception
  when others then
    remove_probe;
    rollback;
    raise;
end;
/
