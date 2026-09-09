-- Run as NFE_OWNER in PDB_POCRT_02.
-- Creates the single-consumer RAW Transactional Event Queue used only for
-- small migration-reference envelopes, never XML/CLOB/BLOB payloads.
-- The script is idempotent for the expected queue names and does not drop or
-- alter an existing queue.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_main_queue_count      pls_integer;
  l_exception_queue_count pls_integer;
  l_queue_type            user_queues.queue_type%type;
  l_max_retries           user_queues.max_retries%type;
  l_enqueue_enabled       user_queues.enqueue_enabled%type;
  l_dequeue_enabled       user_queues.dequeue_enabled%type;

  procedure start_missing_directions(
    p_queue_name varchar2,
    p_allow_enqueue boolean) is
    l_start_enqueue boolean;
    l_start_dequeue boolean;
  begin
    select enqueue_enabled, dequeue_enabled
      into l_enqueue_enabled, l_dequeue_enabled
      from user_queues
     where name = p_queue_name;

    l_start_enqueue := p_allow_enqueue and l_enqueue_enabled = 'NO';
    l_start_dequeue := l_dequeue_enabled = 'NO';

    if l_start_enqueue or l_start_dequeue then
      dbms_aqadm.start_queue(
        queue_name => p_queue_name,
        enqueue => l_start_enqueue,
        dequeue => l_start_dequeue);
      dbms_output.put_line('Started missing direction(s) for ' || p_queue_name || '.');
    else
      dbms_output.put_line(p_queue_name || ' is already started.');
    end if;
  end;
begin
  select count(*)
    into l_main_queue_count
    from user_queues
   where name = 'NFE_MIGRATION_Q';

  if l_main_queue_count = 0 then
    dbms_aqadm.create_transactional_event_queue(
      queue_name         => 'NFE_MIGRATION_Q',
      multiple_consumers => false,
      max_retries        => 3,
      comment            => 'PoC NF-e reference work queue; RAW UTF-8 JSON only',
      queue_payload_type => 'RAW');
    dbms_output.put_line('Created TEQ NFE_MIGRATION_Q.');
  else
    select queue_type, max_retries
      into l_queue_type, l_max_retries
      from user_queues
     where name = 'NFE_MIGRATION_Q';

    if l_queue_type <> 'NORMAL_QUEUE' or nvl(l_max_retries, -1) <> 3 then
      raise_application_error(-20080,
        'NFE_MIGRATION_Q exists with an unexpected type or MAX_RETRIES. No change was made.');
    end if;
    dbms_output.put_line('TEQ NFE_MIGRATION_Q already exists with expected policy.');
  end if;

  select count(*)
    into l_exception_queue_count
    from user_queues
   where name = 'NFE_MIGRATION_EX_Q';

  if l_exception_queue_count = 0 then
    -- Positional notation is deliberate: Oracle 26ai package metadata in
    -- managed deployments has exposed different formal names for the first
    -- argument, while its first two VARCHAR2 parameters are stable.
    dbms_aqadm.create_eq_exception_queue(
      'NFE_MIGRATION_Q', 'NFE_MIGRATION_EX_Q');
    dbms_output.put_line('Created TEQ exception queue NFE_MIGRATION_EX_Q.');
  else
    select queue_type
      into l_queue_type
      from user_queues
     where name = 'NFE_MIGRATION_EX_Q';

    if l_queue_type <> 'EXCEPTION_QUEUE' then
      raise_application_error(-20081,
        'NFE_MIGRATION_EX_Q exists but is not an exception queue. No change was made.');
    end if;
    dbms_output.put_line('TEQ exception queue NFE_MIGRATION_EX_Q already exists.');
  end if;

  start_missing_directions('NFE_MIGRATION_Q', true);
  -- Exception queues must not accept enqueue. In Oracle 26ai this queue is
  -- created dequeue-enabled, so the helper normally performs no operation.
  start_missing_directions('NFE_MIGRATION_EX_Q', false);

  dbms_output.put_line('PASS: TEQ and exception queue are started.');
end;
/
