-- Run as NFE_OWNER after worker/config packages are deployed.
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

create or replace package pkg_nfe_scheduler authid definer as
  procedure run_selection;
  procedure run_workers;
  procedure run_reconciliation;
end;
/
create or replace package body pkg_nfe_scheduler as
  procedure run_selection is
    l_paused char(1); l_inflight number; l_chunk number; l_workers number; l_idle number; l_run number;
  begin
    pkg_nfe_pipeline_config.get_config(l_paused,l_inflight,l_chunk,l_workers,l_idle,l_run);
    if l_paused='Y' then return; end if;
    -- Batch discovery/close is added with reconciliation; this bounded entry
    -- point intentionally performs no implicit admission.
  end;
  procedure run_workers is
    l_paused char(1); l_inflight number; l_chunk number; l_workers number; l_idle number; l_run number;
    l_deadline timestamp with time zone;
  begin
    pkg_nfe_pipeline_config.get_config(l_paused,l_inflight,l_chunk,l_workers,l_idle,l_run);
    if l_paused='Y' then return; end if;
    l_deadline:=systimestamp + numtodsinterval(l_run,'MINUTE');
    for n in 1..l_workers loop
      exit when systimestamp >= l_deadline;
      pkg_nfe_pipeline_config.get_config(l_paused,l_inflight,l_chunk,l_workers,l_idle,l_run);
      exit when l_paused='Y';
      begin
        pkg_nfe_worker.process_one(false);
      exception when others then
        if sqlcode=-25228 then return; end if; raise;
      end;
    end loop;
  end;
  procedure run_reconciliation is
    l_paused char(1); l_inflight number; l_chunk number; l_workers number; l_idle number; l_run number;
  begin
    pkg_nfe_pipeline_config.get_config(l_paused,l_inflight,l_chunk,l_workers,l_idle,l_run);
    if l_paused='Y' then return; end if;
    -- The reconciliation package is deployed by task 5.3; no state is changed here.
  end;
end;
/
declare
  procedure create_disabled(p_name varchar2,p_action varchar2) is
  begin
    begin dbms_scheduler.drop_job(p_name, force=>true); exception when others then if sqlcode<>-27475 then raise; end if; end;
    dbms_scheduler.create_job(job_name=>p_name,job_type=>'PLSQL_BLOCK',job_action=>p_action,
      start_date=>null,repeat_interval=>'FREQ=MINUTELY;INTERVAL=1',enabled=>false,auto_drop=>false);
  end;
begin
  create_disabled('NFE_MIGRATION_SELECTION_JOB','begin pkg_nfe_scheduler.run_selection; end;');
  create_disabled('NFE_MIGRATION_WORKER_JOB','begin pkg_nfe_scheduler.run_workers; end;');
  create_disabled('NFE_MIGRATION_RECONCILIATION_JOB','begin pkg_nfe_scheduler.run_reconciliation; end;');
end;
/
prompt PASS: disabled selection, worker and reconciliation jobs created.
