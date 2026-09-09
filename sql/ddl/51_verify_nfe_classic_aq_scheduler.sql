-- Run as NFE_OWNER after ddl/50_create_nfe_classic_aq_scheduler.sql.
-- Validates paused/idle bounded behavior and confirms TEQ Scheduler jobs stay
-- present and disabled. It neither enables nor runs a Scheduler job.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_count    pls_integer;
  l_paused   char(1);
  l_inflight number;
  l_chunk    number;
  l_workers  number;
  l_idle     number;
  l_run      number;
begin
  select count(*) into l_count
    from user_scheduler_jobs
   where job_name = 'NFE_CLASSIC_AQ_WORKER_JOB'
     and enabled = 'FALSE';
  if l_count <> 1 then
    raise_application_error(-20281,
      'Classic AQ worker job must exist and remain disabled by default.');
  end if;
  select count(*) into l_count
    from user_scheduler_jobs
   where job_name in ('NFE_MIGRATION_SELECTION_JOB', 'NFE_MIGRATION_WORKER_JOB',
                       'NFE_MIGRATION_RECONCILIATION_JOB')
     and enabled = 'FALSE';
  if l_count <> 3 then
    raise_application_error(-20282,
      'Existing TEQ scheduler jobs are not all present and disabled.');
  end if;

  pkg_nfe_pipeline_config.get_config(
    l_paused, l_inflight, l_chunk, l_workers, l_idle, l_run);
  pkg_nfe_pipeline_config.set_config('Y', l_inflight, l_chunk, l_workers, l_idle, l_run);
  pkg_nfe_classic_aq_scheduler.run_workers;
  rollback;

  dbms_output.put_line('PASS: classic AQ bounded runner exits while paused; classic and TEQ jobs remain disabled.');
end;
/
