-- Run as NFE_OWNER in PDB_POCRT_02 after validation/13 and validation/14.
-- Creates a persistent classic-AQ transport. It never references, alters, or
-- consumes NFE_MIGRATION_Q or NFE_MIGRATION_EX_Q (the TEQ evidence path).

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  c_queue_table constant varchar2(30) := 'NFE_CLASSIC_AQ_QT';
  c_queue       constant varchar2(30) := 'NFE_CLASSIC_AQ_Q';
  c_exception   constant varchar2(30) := 'NFE_CLASSIC_AQ_EX_Q';
  l_count       pls_integer;
  l_object_type user_queue_tables.object_type%type;
  l_recipients  user_queue_tables.recipients%type;
  l_queue_table user_queues.queue_table%type;
  l_queue_type  user_queues.queue_type%type;
  l_retries     user_queues.max_retries%type;
  l_delay       user_queues.retry_delay%type;

  procedure require_normal_queue is
  begin
    select queue_table, queue_type, max_retries, retry_delay
      into l_queue_table, l_queue_type, l_retries, l_delay
      from user_queues
     where name = c_queue;

    if l_queue_table <> c_queue_table
       or l_queue_type <> 'NORMAL_QUEUE'
       or nvl(l_retries, -1) <> 3
       or nvl(l_delay, -1) <> 0 then
      raise_application_error(-20150,
        c_queue || ' exists with an unexpected classic-AQ policy; no change was made.');
    end if;
  end;

  procedure require_exception_queue is
  begin
    select queue_table, queue_type
      into l_queue_table, l_queue_type
      from user_queues
     where name = c_exception;

    if l_queue_table <> c_queue_table or l_queue_type <> 'EXCEPTION_QUEUE' then
      raise_application_error(-20151,
        c_exception || ' exists with an unexpected type; no change was made.');
    end if;
  end;
begin
  select count(*) into l_count from user_queue_tables where queue_table = c_queue_table;
  if l_count = 0 then
    -- This is persistent, non-sharded, single-consumer classic AQ. The API
    -- defaults to the database-supported classic compatibility level (10.0.0
    -- on the validated target) and uses no TEQ or sharded-queue feature.
    dbms_aqadm.create_queue_table(
      queue_table        => c_queue_table,
      queue_payload_type => 'RAW',
      multiple_consumers => false,
      comment            => 'PoC NF-e classic AQ reference envelopes; RAW only');
    dbms_output.put_line('Created classic AQ queue table ' || c_queue_table || '.');
  else
    select object_type, recipients
      into l_object_type, l_recipients
      from user_queue_tables
     where queue_table = c_queue_table;

    if l_object_type is not null or l_recipients <> 'SINGLE' then
      raise_application_error(-20152,
        c_queue_table || ' exists but is not the expected RAW single-consumer queue table.');
    end if;
    dbms_output.put_line('Classic AQ queue table already has the expected shape.');
  end if;

  select count(*) into l_count from user_queues where name = c_queue;
  if l_count = 0 then
    dbms_aqadm.create_queue(
      queue_name  => c_queue,
      queue_table => c_queue_table,
      queue_type  => dbms_aqadm.normal_queue,
      max_retries => 3,
      retry_delay => 0,
      comment     => 'PoC NF-e classic AQ work queue; reference envelopes only');
    dbms_output.put_line('Created classic AQ normal queue ' || c_queue || '.');
  else
    require_normal_queue;
    dbms_output.put_line('Classic AQ normal queue already has the expected policy.');
  end if;

  select count(*) into l_count from user_queues where name = c_exception;
  if l_count = 0 then
    dbms_aqadm.create_queue(
      queue_name  => c_exception,
      queue_table => c_queue_table,
      queue_type  => dbms_aqadm.exception_queue,
      comment     => 'PoC NF-e classic AQ exception queue; correlation only');
    dbms_output.put_line('Created classic AQ exception queue ' || c_exception || '.');
  else
    require_exception_queue;
    dbms_output.put_line('Classic AQ exception queue already has the expected type.');
  end if;

  dbms_aqadm.start_queue(c_queue, true, true);
  dbms_aqadm.start_queue(c_exception, false, true);
  dbms_output.put_line('PASS: persistent classic AQ transport is started.');
end;
/
