whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
prompt Load the protected local environment file containing administrator values only.
@@environment.sql
declare
  l_enabled char(1);
  l_job varchar2(5);
begin
  select classic_aq_enabled into l_enabled from nfe_classic_aq_config where config_id=1;
  select enabled into l_job from user_scheduler_jobs where job_name='NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB';
  if l_enabled <> 'N' or l_job <> 'FALSE' then
    raise_application_error(-20850,'Configuration must leave the Classic AQ gate and job disabled.');
  end if;
  dbms_output.put_line('PASS: environment configuration persisted; Classic AQ, job, and batch selection remain disabled.');
end;
/
