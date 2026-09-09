-- Run as NFE_OWNER for the operational rollback of the classic AQ transport.
-- This is reversible: it disables only the classic-AQ gate and its own job.
-- It does not stop, drop, purge, dequeue, migrate, or otherwise alter either
-- classic-AQ messages or the TEQ queues and ADR evidence.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_paused    char(1);
  l_inflight  number;
  l_chunk     number;
  l_workers   number;
  l_idle      number;
  l_run       number;
  l_job_count pls_integer;
  l_job_enabled user_scheduler_jobs.enabled%type;
begin
  pkg_nfe_classic_aq_config.set_classic_aq_enabled('N');

  select count(*) into l_job_count
    from user_scheduler_jobs
   where job_name = 'NFE_CLASSIC_AQ_WORKER_JOB';
  if l_job_count <> 1 then
    raise_application_error(-20300,
      'Classic AQ worker job is absent; operational rollback was not completed.');
  end if;
  select enabled into l_job_enabled
    from user_scheduler_jobs
   where job_name = 'NFE_CLASSIC_AQ_WORKER_JOB';
  if l_job_enabled = 'TRUE' then
    dbms_scheduler.disable('NFE_CLASSIC_AQ_WORKER_JOB');
  end if;

  pkg_nfe_audit.log_event(
    p_actor_type => 'USER',
    p_event_type => 'CLASSIC_AQ_OPERATIONAL_ROLLBACK',
    p_details_json => '{"transportMode":"CLASSIC_AQ","enabled":"N"}');
  commit;
  dbms_output.put_line('PASS: classic AQ gate and classic job are disabled; queues and messages were not touched.');
end;
/
