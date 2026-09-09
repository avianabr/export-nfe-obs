-- Run as NFE_OWNER after 27_create_nfe_scheduler_jobs.sql.
whenever sqlerror exit failure rollback
set serveroutput on size unlimited
declare
  l_disabled number; l_paused char(1); l_inflight number; l_chunk number; l_workers number; l_idle number; l_run number;
begin
  select count(*) into l_disabled from user_scheduler_jobs
   where job_name in ('NFE_MIGRATION_SELECTION_JOB','NFE_MIGRATION_WORKER_JOB','NFE_MIGRATION_RECONCILIATION_JOB')
     and enabled='FALSE';
  if l_disabled<>3 then raise_application_error(-20120,'Scheduler jobs must exist and be disabled.'); end if;
  pkg_nfe_pipeline_config.get_config(l_paused,l_inflight,l_chunk,l_workers,l_idle,l_run);
  pkg_nfe_pipeline_config.set_config('Y',l_inflight,l_chunk,l_workers,l_idle,l_run);
  pkg_nfe_scheduler.run_selection; pkg_nfe_scheduler.run_workers; pkg_nfe_scheduler.run_reconciliation;
  rollback;
  dbms_output.put_line('PASS: disabled jobs are configured; bounded runners exit safely while paused or idle.');
end;
/
