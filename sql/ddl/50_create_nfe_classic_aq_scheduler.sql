-- Run as NFE_OWNER after the classic AQ worker/config packages are deployed.
-- Creates one separate, disabled-by-default scheduler job. It does not drop,
-- enable, disable, or alter any NFE_MIGRATION_* TEQ scheduler job.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

create or replace package pkg_nfe_classic_aq_scheduler authid definer as
  procedure run_workers;
end pkg_nfe_classic_aq_scheduler;
/

create or replace package body pkg_nfe_classic_aq_scheduler as
  procedure run_workers is
    l_paused    char(1);
    l_inflight  number;
    l_chunk     number;
    l_workers   number;
    l_idle      number;
    l_run       number;
    l_enabled   char(1);
    l_deadline  timestamp with time zone;
    l_active    pls_integer;
  begin
    pkg_nfe_pipeline_config.get_config(
      l_paused, l_inflight, l_chunk, l_workers, l_idle, l_run);
    if l_paused = 'Y' then
      return;
    end if;
    pkg_nfe_classic_aq_config.get_classic_aq_enabled(l_enabled);
    if l_enabled <> 'Y' then
      return;
    end if;

    select count(*) into l_active
      from nfe_migration_item i
     where i.status in ('QUEUED', 'UPLOADING', 'UPLOADED', 'VERIFYING')
       and exists (
             select 1
               from nfe_migration_batch_transport t
              where t.batch_id = i.batch_id
                and t.transport_mode = 'CLASSIC_AQ');
    if l_active > l_inflight then
      raise_application_error(-20280,
        'Classic AQ active-item count exceeds the configured inflight limit.');
    end if;

    l_deadline := systimestamp + numtodsinterval(l_run, 'MINUTE');
    for l_worker in 1 .. l_workers loop
      exit when systimestamp >= l_deadline;
      pkg_nfe_pipeline_config.get_config(
        l_paused, l_inflight, l_chunk, l_workers, l_idle, l_run);
      exit when l_paused = 'Y';
      begin
        pkg_nfe_classic_aq_worker.process_one(false);
      exception
        when others then
          -- An empty classic queue is a normal bounded-run termination, not a
          -- job failure. Any other error is retained for Scheduler diagnostics.
          if sqlcode = -25228 then
            return;
          end if;
          raise;
      end;
    end loop;
  end run_workers;
end pkg_nfe_classic_aq_scheduler;
/

declare
  l_count pls_integer;
begin
  select count(*) into l_count
    from user_scheduler_jobs
   where job_name = 'NFE_CLASSIC_AQ_WORKER_JOB';
  if l_count = 0 then
    dbms_scheduler.create_job(
      job_name => 'NFE_CLASSIC_AQ_WORKER_JOB',
      job_type => 'PLSQL_BLOCK',
      job_action => 'begin pkg_nfe_classic_aq_scheduler.run_workers; end;',
      start_date => null,
      repeat_interval => 'FREQ=MINUTELY;INTERVAL=1',
      enabled => false,
      auto_drop => false,
      comments => 'Disabled-by-default classic AQ PoC worker; separate from TEQ jobs.');
    dbms_output.put_line('Created disabled NFE_CLASSIC_AQ_WORKER_JOB.');
  else
    dbms_output.put_line('NFE_CLASSIC_AQ_WORKER_JOB already exists; its state was not changed.');
  end if;
end;
/

prompt PASS: classic AQ bounded scheduler entry point and disabled job created.
