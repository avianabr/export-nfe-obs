-- Run as NFE_OWNER after ddl/54_disable_nfe_classic_aq_transport.sql.
-- Compare TEQ metadata and state counts with the preservation baseline from
-- validation/12. Defaults are the recorded 2026-09-08 baseline values; amend
-- only if a later approved baseline has replaced that evidence.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

accept expected_teq_processed number default 96 prompt 'Expected TEQ PROCESSED count [96]: '
accept expected_teq_ready number default 2 prompt 'Expected TEQ READY count [2]: '
accept expected_teq_retryexpired number default 6 prompt 'Expected TEQ RETRYEXPIRED count [6]: '

declare
  l_enabled      char(1);
  l_job_enabled  user_scheduler_jobs.enabled%type;
  l_queue_count  pls_integer;
  l_processed    pls_integer;
  l_ready        pls_integer;
  l_retryexpired pls_integer;
begin
  pkg_nfe_classic_aq_config.get_classic_aq_enabled(l_enabled);
  if l_enabled <> 'N' then
    raise_application_error(-20301, 'Classic AQ gate remains enabled.');
  end if;
  select enabled into l_job_enabled
    from user_scheduler_jobs
   where job_name = 'NFE_CLASSIC_AQ_WORKER_JOB';
  if l_job_enabled <> 'FALSE' then
    raise_application_error(-20302, 'Classic AQ worker job remains enabled.');
  end if;

  select count(*) into l_queue_count
    from user_queues
   where name in ('NFE_MIGRATION_Q', 'NFE_MIGRATION_EX_Q');
  if l_queue_count <> 2 then
    raise_application_error(-20303, 'TEQ queue metadata changed or is incomplete.');
  end if;
  select count(*) into l_processed from aq$nfe_migration_q where msg_state = 'PROCESSED';
  select count(*) into l_ready from aq$nfe_migration_q where msg_state = 'READY';
  select count(*) into l_retryexpired from aq$nfe_migration_q where msg_state = 'RETRYEXPIRED';
  if l_processed <> &expected_teq_processed
     or l_ready <> &expected_teq_ready
     or l_retryexpired <> &expected_teq_retryexpired then
    raise_application_error(-20304,
      'TEQ message counts differ from the approved preservation baseline.');
  end if;

  dbms_output.put_line('PASS: classic AQ rollback is active and TEQ queues/counts match the preservation baseline.');
end;
/
